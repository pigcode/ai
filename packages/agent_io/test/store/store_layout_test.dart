import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late StoreLayout layout;
  final sessionId = SessionId.parse('ses_7z000000000000000000000000000000');

  setUp(() {
    temporary = Directory.systemTemp.createTempSync(
      'pigcode-agent-store-layout-',
    );
    root = Directory.fromUri(temporary.uri.resolve('store/'))..createSync();
    layout = StoreLayout.open(root);
  });

  tearDown(() {
    temporary.deleteSync(recursive: true);
  });

  test('derives the session shard only from a typed SessionId', () {
    expect(layout.sessionShard(sessionId), '7z');
    expect(
      layout.sessionDirectory(sessionId).path,
      endsWith(
        'sessions${Platform.pathSeparator}7z'
        '${Platform.pathSeparator}${sessionId.value}',
      ),
    );
    expect(
      layout.identityChunks(sessionId).path,
      endsWith(
        '${sessionId.value}${Platform.pathSeparator}identities'
        '${Platform.pathSeparator}chunks',
      ),
    );
    expect(
      () => SessionId.parse('ses_../../outside'),
      throwsFormatException,
    );
  });

  test('content-addressed names reject path fragments and uppercase', () {
    expect(
      () => layout.identityChunkFile(
        sessionId,
        '../${''.padLeft(64, '0')}',
      ),
      throwsLayoutCode(StoreLayoutErrorCode.invalidArtifactName),
    );
    expect(
      () => layout.commandChunkFile(sessionId, ''.padLeft(64, 'A')),
      throwsLayoutCode(StoreLayoutErrorCode.invalidArtifactName),
    );
    final digest = ''.padLeft(64, 'a');
    final file = layout.identityChunkFile(sessionId, digest);
    expect(file.path, endsWith('$digest.json'));
  });

  test('tree validation rejects symlinks', () {
    final outside = File.fromUri(temporary.uri.resolve('outside'))
      ..writeAsStringSync('outside');
    Link.fromUri(root.uri.resolve('linked')).createSync(outside.path);

    expect(
      layout.validateExistingTree,
      throwsLayoutCode(StoreLayoutErrorCode.symlinkRejected),
    );
  });

  test('opening a symlink root is rejected', () {
    final link = Link.fromUri(temporary.uri.resolve('store-link'))
      ..createSync(root.path);

    expect(
      () => StoreLayout.open(Directory(link.path)),
      throwsLayoutCode(StoreLayoutErrorCode.symlinkRejected),
    );
  });

  test('artifact validation rejects directories and paths outside root', () {
    expect(
      () => layout.validateExistingArtifact(File(layout.root.path)),
      throwsLayoutCode(StoreLayoutErrorCode.unexpectedEntity),
    );
    final outside = File.fromUri(temporary.uri.resolve('outside.bin'))
      ..writeAsBytesSync(<int>[1]);
    expect(
      () => layout.validateExistingArtifact(outside),
      throwsLayoutCode(StoreLayoutErrorCode.outsideRoot),
    );
  });
}

Matcher throwsLayoutCode(StoreLayoutErrorCode code) => throwsA(
      isA<StoreLayoutException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
