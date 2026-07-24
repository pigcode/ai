import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

const _peerPath = 'tool/fixtures/lsp_peer.dart';
const _deadline = Duration(seconds: 15);

Future<void> main() async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    const <String>[_peerPath],
    workingDirectory: Directory.current.absolute.path,
  );
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final iterator = StreamIterator<List<int>>(
    process.stdout.transform(_ContentLengthDecoder()),
  );
  try {
    _send(
      process,
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 1,
        'method': 'initialize',
        'params': <String, Object?>{
          'processId': null,
          'rootUri': null,
          'capabilities': <String, Object?>{},
        },
      },
    );
    final initialize = await _next(iterator);
    final decodedInitialize = LspCodec.instance.decode(
      utf8.decode(initialize),
      sender: LspMessageSender.server,
      responseMethod: 'initialize',
    );
    _expect(
      decodedInitialize.methodDescriptor.method == 'initialize',
      'initialize response was not correlated',
    );

    _send(
      process,
      const <String, Object?>{
        'jsonrpc': '2.0',
        'id': 2,
        'method': 'shutdown',
      },
    );
    LspCodec.instance.decode(
      utf8.decode(await _next(iterator)),
      sender: LspMessageSender.server,
      responseMethod: 'shutdown',
    );
    _send(
      process,
      const <String, Object?>{
        'jsonrpc': '2.0',
        'method': 'exit',
      },
    );
    await process.stdin.close();
    final code = await process.exitCode.timeout(_deadline);
    final stderrText = await stderrFuture;
    _expect(code == 0, 'LSP peer exited with $code: $stderrText');
    stdout.writeln('PASS LSP Dart real process');
  } finally {
    await iterator.cancel();
    if (await _isRunning(process)) {
      process.kill();
      await process.exitCode.timeout(_deadline);
    }
  }
}

void _send(Process process, Map<String, Object?> envelope) {
  final body = utf8.encode(jsonEncode(envelope));
  process.stdin.add(<int>[
    ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
    ...body,
  ]);
}

Future<List<int>> _next(StreamIterator<List<int>> iterator) async {
  final available = await iterator.moveNext().timeout(_deadline);
  if (!available) {
    throw StateError('LSP peer closed before the expected response.');
  }
  return iterator.current;
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _ContentLengthDecoder
    extends StreamTransformerBase<List<int>, List<int>> {
  @override
  Stream<List<int>> bind(Stream<List<int>> stream) async* {
    final framer = ContentLengthFramer();
    await for (final chunk in stream) {
      for (final frame in framer.add(chunk)) {
        yield frame;
      }
    }
    for (final frame in framer.close()) {
      yield frame;
    }
  }
}
