import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('requires version negotiation before ordinary operations', () {
    final connection = AnalysisServerConnection();

    expect(
      () => connection.beginRequest(
        'analysis.getHover',
        params: const <String, Object?>{
          'file': '/workspace/main.dart',
          'offset': 0
        },
      ),
      throwsA(isA<ToolingProtocolStateError>()),
    );

    final version = connection.beginVersionQuery();
    expect(version.id, '1');
    expect(version.method, 'server.getVersion');
    expect(
        connection.lifecycle, AnalysisServerConnectionLifecycle.versionPending);

    connection.completeVersionQuery(
      version.id,
      const <String, Object?>{'version': '1.38.0'},
      clientCapabilities: const <String, Object?>{
        'requests': <Object?>['server.showMessageRequest'],
        'supportsUris': true,
      },
    );

    expect(connection.lifecycle, AnalysisServerConnectionLifecycle.ready);
    expect(
      connection.capabilities.apiVersion,
      analysisServerMinimumApiVersion,
    );
    expect(
      connection.capabilities.advertisesClientRequest(
        'server.showMessageRequest',
      ),
      isTrue,
    );
  });

  test('rejects an unsupported API major and current-only feature on minimum',
      () {
    final incompatible = AnalysisServerConnection();
    final version = incompatible.beginVersionQuery();
    expect(
      () => incompatible.completeVersionQuery(
        version.id,
        const <String, Object?>{'version': '2.0.0'},
      ),
      throwsA(
        isA<ToolingVersionError>().having(
          (error) => error.code,
          'code',
          'analysis_server_api_major_unsupported',
        ),
      ),
    );
    expect(incompatible.lifecycle, AnalysisServerConnectionLifecycle.closed);

    final minimum = _readyConnection();
    expect(
      () => minimum.receiveNotification(
        'server.pluginError',
        const <String, Object?>{
          'isFatal': false,
          'message': 'future-only notification',
          'stackTrace': '',
        },
      ),
      throwsA(isA<ToolingVersionError>()),
    );
  });

  test('shutdown closes the connection and reconnect gets a new identity', () {
    final connection = _readyConnection();
    final shutdown = connection.beginShutdown();

    expect(
      connection.lifecycle,
      AnalysisServerConnectionLifecycle.shuttingDown,
    );
    expect(shutdown.method, 'server.shutdown');

    connection.completeResponse(
      id: shutdown.id,
      method: shutdown.method,
    );
    expect(connection.lifecycle, AnalysisServerConnectionLifecycle.closed);

    final replacement = connection.reconnect();
    expect(replacement.connectionId, isNot(connection.connectionId));
    expect(replacement.lifecycle, AnalysisServerConnectionLifecycle.created);
  });
}

AnalysisServerConnection _readyConnection() {
  final connection = AnalysisServerConnection();
  final version = connection.beginVersionQuery();
  connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'version': '1.38.0'},
  );
  return connection;
}
