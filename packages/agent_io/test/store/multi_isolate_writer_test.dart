import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import 'file_store_test_support.dart';

void main() {
  late FileStoreFixture fixture;

  setUp(() async {
    fixture = await FileStoreFixture.create();
    await fixture.createSession();
  });

  tearDown(() async {
    await fixture.dispose();
  });

  test('two worker isolates share one coordinator capability', () async {
    final response1 = ReceivePort();
    final response2 = ReceivePort();
    final iterator1 = StreamIterator<Object?>(response1);
    final iterator2 = StreamIterator<Object?>(response2);
    await Isolate.spawn<List<Object?>>(
      _writerIsolate,
      <Object?>[
        fixture.coordinator.capability,
        fixture.root.path,
        1,
        response1.sendPort,
      ],
    );
    await Isolate.spawn<List<Object?>>(
      _writerIsolate,
      <Object?>[
        fixture.coordinator.capability,
        fixture.root.path,
        2,
        response2.sendPort,
      ],
    );

    expect(
      await Future.wait<bool>(
        <Future<bool>>[iterator1.moveNext(), iterator2.moveNext()],
      ),
      everyElement(isTrue),
    );
    final ready1 = iterator1.current! as Map<Object?, Object?>;
    final ready2 = iterator2.current! as Map<Object?, Object?>;
    (ready1['gate']! as SendPort).send('go');
    (ready2['gate']! as SendPort).send('go');

    expect(
      await Future.wait<bool>(
        <Future<bool>>[iterator1.moveNext(), iterator2.moveNext()],
      ).timeout(const Duration(seconds: 10)),
      everyElement(isTrue),
    );
    final results = <Map<Object?, Object?>>[
      iterator1.current! as Map<Object?, Object?>,
      iterator2.current! as Map<Object?, Object?>,
    ];
    await iterator1.cancel();
    await iterator2.cancel();
    response1.close();
    response2.close();

    expect(
      results.where((result) => result['ok'] == true),
      hasLength(1),
    );
    expect(
      results
          .where((result) => result['ok'] == false)
          .map((result) => result['code']),
      <String>[AgentStoreErrorCode.sequenceConflict.name],
    );
    final page = await fixture.store.readEvents(fileTestSessionId);
    expect(page.events.map((event) => event.sequence), <int>[1, 2]);
  });
}

Future<void> _writerIsolate(List<Object?> arguments) async {
  final capability = arguments[0]! as FileStoreCoordinatorCapability;
  final root = Directory(arguments[1]! as String);
  final variant = arguments[2]! as int;
  final response = arguments[3]! as SendPort;
  final gate = ReceivePort();
  try {
    final store = await FileAgentStore.open(
      root: root,
      coordinator: capability.connect(),
      options: const FileStoreOptions(
        rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
      ),
    );
    final expected = (await store.loadSession(fileTestSessionId)).head;
    response.send(<String, Object?>{
      'gate': gate.sendPort,
      'ready': true,
      'variant': variant,
    });
    await gate.first;
    try {
      final receipt = await store.append(
        fileAppendTransaction(expected, variant: variant),
      );
      response.send(<String, Object?>{
        'afterSequence': receipt.afterHead.sequence,
        'ok': true,
        'variant': variant,
      });
    } on AgentStoreException catch (error) {
      response.send(<String, Object?>{
        'code': error.code.name,
        'ok': false,
        'variant': variant,
      });
    }
  } finally {
    gate.close();
  }
}
