import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart' as anthropic;
import 'package:pigcode_ai_openai/pigcode_ai_openai.dart' as openai;
import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart'
    as compatible;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;

const _peerPath = 'tool/fixtures/ai_core_peer.dart';
const _peerVersion = 'phase1-ai-core-peer-v1';
const _deadline = Duration(seconds: 5);

// Compatibility fixture (real-process): P1-CROSS-01
// Compatibility fixture (real-process): P1-CROSS-02
// Compatibility fixture (real-process): P1-CROSS-03
// Compatibility fixture (real-process): P1-CROSS-04
// Compatibility fixture (real-process): P1-CROSS-05
Future<void> main() async {
  final stopwatch = Stopwatch()..start();
  final peer = await _PeerSession.start();
  final client = HttpClient()..findProxy = (_) => 'DIRECT';
  try {
    _expect(
      stopwatch.elapsed < _deadline,
      'Fixed peer missed the five-second startup deadline.',
    );
    _expect(peer.ready['version'] == _peerVersion, 'Unexpected peer version.');
    _expect(
      peer.ready['sourceBlobHash'] == _sourceBlobHash(),
      'Fixed peer source hash did not fail closed.',
    );

    final baseUri = Uri(
      scheme: 'http',
      host: peer.ready['host'] as String,
      port: peer.ready['port'] as int,
    );
    final echoed = await _postEcho(client, baseUri);
    final body = echoed['body'] as Map<String, Object?>;

    final implementations = <provider.Provider>[
      openai.createOpenAi(
        apiKey: 'fixed-test-key',
        baseUrl: baseUri.toString(),
      ),
      compatible.createOpenAiCompatible(
        name: 'fixed-compatible',
        baseUrl: baseUri.toString(),
      ),
      anthropic.createAnthropic(
        apiKey: 'fixed-test-key',
        baseUrl: baseUri.toString(),
      ),
    ];
    for (final implementation in implementations) {
      final ai.Provider coreView = implementation;
      _expect(
        identical(coreView, implementation),
        'Real-process adapter lost the shared Provider identity.',
      );
    }

    final metadata = _providerMetadata(body['providerMetadata']);
    final ai.ProviderMetadata coreMetadata = metadata;
    _expect(
      coreMetadata['fixed-peer']?['traceId'] == 'cross-process-1',
      'Peer metadata was not preserved across public barrels.',
    );

    final error = provider.ApiCallError(
      message: body['errorMessage'] as String,
      url: baseUri.toString(),
      requestBody: const <String, Object?>{'fixture': 'P1-CROSS-03'},
      statusCode: body['statusCode'] as int,
      data: metadata,
    );
    final ai.ApiCallError coreError = error;
    _expect(
      identical(coreError, error) && coreError.isRetryable,
      'Peer error lost the shared retry/error contract.',
    );

    final controller = ai.CancellationController();
    final cancelledDelay = utils.delayCancellable(
      const Duration(seconds: 5),
      cancellation: controller.signal,
    );
    controller.cancel(body['cancelReason']);
    _expect(
      await _captureFutureError(cancelledDelay) is StateError,
      'Peer cancellation was wrapped as an API error.',
    );
    _expect(
      controller.signal.reason == 'fixed peer cancellation',
      'Peer cancellation reason was not preserved.',
    );

    _expect(
      compatible.mapOpenAiCompatibleFinishReason('stop').unified ==
          provider.FinishReasonType.stop,
      'Portable public surface lost the shared finish-reason enum.',
    );

    final shutdown = await peer.request(<String, Object?>{
      'id': 'cross-shutdown',
      'op': 'shutdown',
    });
    _expect(shutdown['shutdown'] == true, 'Peer did not acknowledge shutdown.');
    _expect(
        await peer.process.exitCode.timeout(_deadline) == 0, 'Peer failed.');
    _expect(
        (await peer.stderrOutput).trim().isEmpty, 'Peer wrote diagnostics.');
    _expect(
      stopwatch.elapsed < const Duration(seconds: 30),
      'Cross-process fixture exceeded its 30-second budget.',
    );
    print('PASS AI Core cross-package real process');
  } finally {
    client.close(force: true);
    await peer.dispose();
  }
}

Future<Map<String, Object?>> _postEcho(HttpClient client, Uri baseUri) async {
  final request = await client.postUrl(baseUri.replace(path: '/echo'));
  request.headers.contentType = ContentType.json;
  request.write(
    jsonEncode(<String, Object?>{
      'providerMetadata': <String, Object?>{
        'fixed-peer': <String, Object?>{
          'traceId': 'cross-process-1',
          'nested': <String, Object?>{'kept': true},
        },
      },
      'errorMessage': 'fixed peer rate limit',
      'statusCode': 429,
      'cancelReason': 'fixed peer cancellation',
    }),
  );
  final response = await request.close().timeout(_deadline);
  final decoded = jsonDecode(
    await utf8.decoder.bind(response).join().timeout(_deadline),
  ) as Map<String, Object?>;
  _expect(
      response.statusCode == HttpStatus.ok, 'Peer echo did not return 200.');
  return decoded;
}

provider.ProviderMetadata _providerMetadata(Object? value) {
  final outer = value as Map<String, Object?>;
  return <String, provider.JsonObject>{
    for (final entry in outer.entries)
      entry.key: Map<String, Object?>.from(entry.value as Map),
  };
}

Future<Object?> _captureFutureError(Future<void> future) async {
  try {
    await future;
  } on Object catch (error) {
    return error;
  }
  return null;
}

String _sourceBlobHash() {
  final result = Process.runSync(
    'git',
    const <String>['hash-object', '--', _peerPath],
  );
  _expect(result.exitCode == 0, 'Unable to hash fixed peer source.');
  final hash = (result.stdout as String).trim();
  _expect(
    RegExp(r'^[a-f0-9]{40}$').hasMatch(hash),
    'Fixed peer source hash is invalid.',
  );
  return hash;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}

final class _PeerSession {
  _PeerSession._(
    this.process,
    this.lines,
    this.ready,
    this.stderrOutput,
  );

  final Process process;
  final StreamIterator<String> lines;
  final Map<String, Object?> ready;
  final Future<String> stderrOutput;

  static Future<_PeerSession> start() async {
    final environment = <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };
    final process = await Process.start(
      Platform.resolvedExecutable,
      const <String>[_peerPath],
      workingDirectory: Directory.current.absolute.path,
      environment: environment,
      includeParentEnvironment: false,
    );
    final lines = StreamIterator<String>(
      process.stdout.transform(utf8.decoder).transform(const LineSplitter()),
    );
    final stderrOutput = process.stderr.transform(utf8.decoder).join();
    try {
      _expect(
        await lines.moveNext().timeout(_deadline),
        'Peer exited before its ready handshake.',
      );
      return _PeerSession._(
        process,
        lines,
        jsonDecode(lines.current) as Map<String, Object?>,
        stderrOutput,
      );
    } on Object {
      process.kill();
      await process.exitCode;
      rethrow;
    }
  }

  Future<Map<String, Object?>> request(Map<String, Object?> request) async {
    process.stdin.writeln(jsonEncode(request));
    await process.stdin.flush();
    _expect(
      await lines.moveNext().timeout(_deadline),
      'Peer stdout closed while awaiting ${request['id']}.',
    );
    return jsonDecode(lines.current) as Map<String, Object?>;
  }

  Future<void> dispose() async {
    await lines.cancel();
    if (await _isRunning(process)) {
      process.kill();
      await process.exitCode;
    }
  }
}

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
}
