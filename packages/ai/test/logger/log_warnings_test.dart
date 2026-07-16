import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:logging/logging.dart';
import 'package:test/test.dart';

void main() {
  group('logWarnings', () {
    test('does nothing for empty warnings', () {
      final records = <LogRecord>[];
      final logger = Logger.detached('test.empty')..level = Level.ALL;
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      logWarnings(warnings: const [], logger: logger);

      expect(records, isEmpty);
    });

    test('logs provider warnings as Level.WARNING records', () {
      final records = <LogRecord>[];
      final logger = Logger.detached('test.warnings')..level = Level.ALL;
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      logWarnings(
        warnings: const [
          UnsupportedWarning('seed', details: 'Ignored by this model.'),
          CompatibilityWarning('responseFormat'),
          DeprecatedWarning('oldSetting', 'Use newSetting instead.'),
          OtherWarning('plain note'),
        ],
        provider: 'openai',
        model: 'gpt-4.1',
        logger: logger,
      );

      expect(records.map((record) => record.level), [
        Level.WARNING,
        Level.WARNING,
        Level.WARNING,
        Level.WARNING,
      ]);
      expect(records.map((record) => record.loggerName), [
        'test.warnings',
        'test.warnings',
        'test.warnings',
        'test.warnings',
      ]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (openai / gpt-4.1): '
            'The feature "seed" is not supported. Ignored by this model.',
        'Pigcode AI Warning (openai / gpt-4.1): '
            'The feature "responseFormat" is used in a compatibility mode.',
        'Pigcode AI Warning (openai / gpt-4.1): '
            'Deprecated: "oldSetting". Use newSetting instead.',
        'Pigcode AI Warning (openai / gpt-4.1): plain note',
      ]);
    });

    test('uses provider-only scope when model is absent', () {
      final records = <LogRecord>[];
      final logger = Logger.detached('test.scope')..level = Level.ALL;
      final subscription = logger.onRecord.listen(records.add);
      addTearDown(subscription.cancel);

      logWarnings(
        warnings: const [OtherWarning('no model')],
        provider: 'openai.files',
        logger: logger,
      );

      expect(records.single.message,
          'Pigcode AI Warning (openai.files): no model');
    });
  });
}
