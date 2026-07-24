import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('keeps status, errors, and analysis notifications ordered', () {
    final connection = _readyConnection(maxNotifications: 3);

    final status = connection.receiveNotification(
      'server.status',
      const <String, Object?>{
        'analysis': <String, Object?>{'isAnalyzing': true},
      },
    );
    final errors = connection.receiveNotification(
      'analysis.errors',
      const <String, Object?>{
        'file': '/workspace/main.dart',
        'errors': <Object?>[],
      },
    );
    final analyzed = connection.receiveNotification(
      'analysis.analyzedFiles',
      const <String, Object?>{
        'directories': <Object?>['/workspace'],
      },
    );

    expect([status.sequence, errors.sequence, analyzed.sequence], [1, 2, 3]);
    expect(connection.notifications.records, [status, errors, analyzed]);
    expect(
      connection.latestStatus,
      const <String, Object?>{
        'analysis': <String, Object?>{'isAnalyzing': true},
      },
    );
    expect(
      connection.latestErrorsByFile['/workspace/main.dart'],
      const <Object?>[],
    );
  });

  test('notification queue is bounded', () {
    final connection = _readyConnection(maxNotifications: 1);
    connection.receiveNotification(
      'server.status',
      const <String, Object?>{},
    );

    expect(
      () => connection.receiveNotification(
        'server.status',
        const <String, Object?>{},
      ),
      throwsA(isA<ToolingResourceLimitError>()),
    );
  });
}

AnalysisServerConnection _readyConnection({required int maxNotifications}) {
  final connection =
      AnalysisServerConnection(maxNotifications: maxNotifications);
  final version = connection.beginVersionQuery();
  connection.completeVersionQuery(
    version.id,
    const <String, Object?>{'version': '1.40.1'},
  );
  return connection;
}
