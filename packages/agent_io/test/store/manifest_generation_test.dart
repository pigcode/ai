import 'dart:io';

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

  test('manifest codec binds immutable generation and filename digest', () {
    const codec = StoreManifestCodec();
    final encoded = codec.encode(<String, Object?>{
      'formatVersion': agentManifestFormatVersion,
      'generation': 9,
      'kind': 'test',
    });
    final file = File(
      '00000000000000000009-${encoded.digest}.json',
    );
    final generation = StoreGenerationFile.tryParse(file)!;

    expect(generation.generation, 9);
    expect(
      codec.decodeGeneration(generation, encoded.bytes)['kind'],
      'test',
    );
    expect(
      () => codec.decodeGeneration(
        StoreGenerationFile(
          file: file,
          generation: 9,
          digest: ''.padLeft(64, '0'),
        ),
        encoded.bytes,
      ),
      throwsA(isA<StoreFormatException>()),
    );
  });

  test('partial temp and invalid highest manifest fall back', () async {
    final directory =
        StoreLayout.open(fixture.root).manifests(fileTestSessionId);
    File.fromUri(directory.uri.resolve('partial.tmp'))
        .writeAsStringSync('partial');
    File.fromUri(directory.uri.resolve(
      '00000000000000000002-${''.padLeft(64, '0')}.json',
    )).writeAsStringSync('partial');

    final session = await fixture.store.loadSession(fileTestSessionId);
    expect(session.head.generation, 1);
  });

  test('future highest manifest fails closed instead of downgrading', () async {
    const codec = StoreManifestCodec();
    final bytes = canonicalJsonBytes(<String, Object?>{
      'formatVersion': 2,
      'generation': 2,
    });
    final digest = storeHex(storeSha256(bytes));
    final directory =
        StoreLayout.open(fixture.root).manifests(fileTestSessionId);
    File.fromUri(directory.uri.resolve(
      '00000000000000000002-$digest.json',
    )).writeAsBytesSync(bytes);

    expect(
      () => fixture.store.loadSession(fileTestSessionId),
      storeError(AgentStoreErrorCode.corruption),
    );
    expect(codec, isNotNull);
  });

  test('root with only corrupt published manifests fails closed', () async {
    final directory = StoreLayout.open(fixture.root).rootManifests;
    final manifests = directory
        .listSync()
        .whereType<File>()
        .where((file) => StoreGenerationFile.tryParse(file) != null)
        .toList();
    expect(manifests, isNotEmpty);
    for (final manifest in manifests) {
      manifest.writeAsStringSync('partial');
    }

    expect(
      fixture.store.loadRoot,
      storeError(AgentStoreErrorCode.corruption),
    );
  });

  test('each mutation publishes a new immutable file without a pointer',
      () async {
    final before = (await fixture.store.loadSession(fileTestSessionId)).head;
    await fixture.store.append(fileAppendTransaction(before));
    final directory =
        StoreLayout.open(fixture.root).manifests(fileTestSessionId);
    final files = directory
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.json'))
        .toList();

    expect(files, hasLength(2));
    expect(
      files.any((file) => file.uri.pathSegments.last == 'manifest.json'),
      isFalse,
    );
  });
}
