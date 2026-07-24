import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('cancel records intent without claiming target completion', () {
    final connection = _readyConnection();
    final target = connection.beginRequest(
      'analysis.getHover',
      params: const <String, Object?>{'file': '/workspace/a.dart', 'offset': 0},
    );
    final cancel = connection.beginCancel(target.id);

    expect(cancel.method, 'server.cancelRequest');
    expect(cancel.params, <String, Object?>{'id': target.id});
    expect(connection.isCancellationRequested(target.id), isTrue);
    expect(target.done, isFalse);

    connection.completeResponse(id: cancel.id, method: cancel.method);
    expect(target.done, isFalse);
    expect(
      () => connection.beginCancel(target.id),
      throwsA(
        isA<ToolingProtocolStateError>().having(
          (error) => error.code,
          'code',
          'analysis_server_cancel_duplicate',
        ),
      ),
    );

    connection.completeResponse(
      id: target.id,
      method: target.method,
      result: const <String, Object?>{'hovers': <Object?>[]},
    );
    expect(target.done, isTrue);
  });

  test('cannot cancel unknown or control requests', () {
    final connection = _readyConnection();

    expect(
      () => connection.beginCancel('404'),
      throwsA(isA<ToolingProtocolStateError>()),
    );
    final shutdown = connection.beginShutdown();
    expect(
      () => connection.beginCancel(shutdown.id),
      throwsA(isA<ToolingProtocolStateError>()),
    );
  });
}

AnalysisServerConnection _readyConnection() {
  final connection = AnalysisServerConnection();
  final version = connection.beginVersionQuery();
  connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'version': '1.40.1'},
  );
  return connection;
}
