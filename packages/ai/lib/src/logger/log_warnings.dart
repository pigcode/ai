import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:logging/logging.dart';

final _defaultLogger = Logger('pigcode_ai.warnings');

/// 通过 Dart logging 基础设施发出 provider 告警。
void logWarnings({
  required Iterable<contracts.Warning> warnings,
  String? provider,
  String? model,
  Logger? logger,
}) {
  final targetLogger = logger ?? _defaultLogger;

  for (final warning in warnings) {
    targetLogger.warning(
      _formatWarning(
        warning: warning,
        provider: provider,
        model: model,
      ),
    );
  }
}

String _formatWarning({
  required contracts.Warning warning,
  required String? provider,
  required String? model,
}) {
  final scope = provider == null
      ? ''
      : model == null
          ? ' ($provider)'
          : ' ($provider / $model)';
  return 'Pigcode AI Warning$scope: ${_formatWarningBody(warning)}';
}

String _formatWarningBody(contracts.Warning warning) {
  return switch (warning) {
    contracts.UnsupportedWarning(:final feature, :final details) =>
      'The feature "$feature" is not supported.${_formatDetails(details)}',
    contracts.CompatibilityWarning(:final feature, :final details) =>
      'The feature "$feature" is used in a compatibility mode.'
          '${_formatDetails(details)}',
    contracts.DeprecatedWarning(:final setting, :final message) =>
      'Deprecated: "$setting". $message',
    contracts.OtherWarning(:final message) => message,
  };
}

String _formatDetails(String? details) {
  if (details == null || details.isEmpty) {
    return '';
  }
  return ' $details';
}
