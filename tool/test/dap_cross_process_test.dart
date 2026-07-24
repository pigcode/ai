import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';

import '../src/tooling_process_harness.dart';

const _deadline = Duration(seconds: 15);

Future<void> main() async {
  final peer = await ToolingProcessHarness.start(
    ToolingProcessCommand(
      executable: Platform.resolvedExecutable,
      arguments: const <String>['tool/fixtures/dap_peer.dart'],
      workingDirectory: Directory.current.absolute.path,
    ),
  );
  var completed = false;
  try {
    await peer.send(const <String, Object?>{
      'seq': 1,
      'type': 'request',
      'command': 'initialize',
      'arguments': <String, Object?>{
        'adapterID': 'pigcode',
        'linesStartAt1': true,
        'columnsStartAt1': true,
      },
    });
    DapCodec.instance.decode(
      _encode(await peer.next(_deadline)),
      requestCommand: 'initialize',
    );
    await peer.send(const <String, Object?>{
      'seq': 2,
      'type': 'request',
      'command': 'launch',
      'arguments': <String, Object?>{},
    });
    DapCodec.instance.decode(
      _encode(await peer.next(_deadline)),
      requestCommand: 'launch',
    );
    final initialized = DapCodec.instance.decode(
      _encode(await peer.next(_deadline)),
    );
    _expect(initialized.name == 'initialized', 'Missing initialized event.');
    await peer.send(const <String, Object?>{
      'seq': 3,
      'type': 'request',
      'command': 'disconnect',
      'arguments': <String, Object?>{},
    });
    DapCodec.instance.decode(
      _encode(await peer.next(_deadline)),
      requestCommand: 'disconnect',
    );
    final terminated = DapCodec.instance.decode(
      _encode(await peer.next(_deadline)),
    );
    _expect(terminated.name == 'terminated', 'Missing terminated event.');
    final code = await peer.close(_deadline);
    completed = true;
    _expect(code == 0, 'DAP peer exited with $code: ${peer.boundedStderr}');
    stdout.writeln('PASS DAP Dart real process');
  } finally {
    if (!completed) {
      await peer.terminate(_deadline);
    }
  }
}

String _encode(Map<String, Object?> value) => jsonEncode(value);

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
