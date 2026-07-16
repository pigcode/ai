import 'package:logging/logging.dart';
import 'package:test/test.dart';

List<LogRecord> captureWarningLogs() {
  final records = <LogRecord>[];
  final rootLevel = Logger.root.level;
  Logger.root.level = Level.ALL;
  final subscription = Logger.root.onRecord
      .where((record) => record.loggerName == 'pigcode_ai.warnings')
      .listen(records.add);
  addTearDown(() async {
    await subscription.cancel();
    Logger.root.level = rootLevel;
  });
  return records;
}
