import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('uses monotonic string ids and correlates id plus method', () {
    final connection = _readyConnection();
    final first = connection.beginRequest(
      'analysis.getHover',
      params: const <String, Object?>{'file': '/workspace/a.dart', 'offset': 0},
    );
    final second = connection.beginRequest(
      'analysis.getHover',
      params: const <String, Object?>{'file': '/workspace/b.dart', 'offset': 1},
    );

    expect(int.parse(second.id), int.parse(first.id) + 1);
    expect(
      () => connection.completeResponse(
        id: first.id,
        method: 'analysis.getNavigation',
        result: const <String, Object?>{
          'files': <Object?>[],
          'regions': <Object?>[],
          'targets': <Object?>[],
        },
      ),
      throwsA(
        isA<ToolingProtocolStateError>().having(
          (error) => error.code,
          'code',
          'analysis_server_response_method_mismatch',
        ),
      ),
    );
    expect(first.done, isFalse);

    connection.completeResponse(
      id: first.id,
      method: first.method,
      result: const <String, Object?>{'hovers': <Object?>[]},
    );
    expect(first.done, isTrue);
    expect(
      () => connection.completeResponse(
        id: first.id,
        method: first.method,
        result: const <String, Object?>{'hovers': <Object?>[]},
      ),
      throwsA(
        isA<ToolingProtocolStateError>().having(
          (error) => error.code,
          'code',
          'analysis_server_response_tombstoned',
        ),
      ),
    );
  });

  test('close completes every pending request exactly once', () {
    final connection = _readyConnection();
    final pending = connection.beginRequest(
      'analysis.getHover',
      params: const <String, Object?>{'file': '/workspace/a.dart', 'offset': 0},
    );

    connection.close();

    expect(pending.done, isTrue);
    expect(pending.failure, isA<ToolingProtocolStateError>());
    expect(() => connection.close(), returnsNormally);
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
