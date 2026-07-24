import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Produces bounded JSON diagnostics without retaining sensitive peer data.
final class DartToolingDiagnosticRedactor {
  const DartToolingDiagnosticRedactor({
    this.maxStringLength = 256,
    this.maxCollectionEntries = 32,
    this.maxDepth = 8,
  })  : assert(maxStringLength > 0),
        assert(maxCollectionEntries > 0),
        assert(maxDepth > 0);

  final int maxStringLength;
  final int maxCollectionEntries;
  final int maxDepth;

  JsonObject redact(JsonObject value) =>
      freezeJsonObject(_redactObject(value, depth: 0));

  Map<String, Object?> _redactObject(
    Map<String, Object?> value, {
    required int depth,
  }) {
    if (depth >= maxDepth) {
      return const <String, Object?>{'value': '<max-depth>'};
    }
    final entries = value.entries.toList(growable: false);
    final retained = entries.take(maxCollectionEntries);
    return <String, Object?>{
      for (final entry in retained)
        entry.key: _redactValue(
          entry.key,
          entry.value,
          depth: depth + 1,
        ),
      if (entries.length > maxCollectionEntries)
        '<truncated>': entries.length - maxCollectionEntries,
    };
  }

  Object? _redactValue(
    String key,
    Object? value, {
    required int depth,
  }) {
    if (_isSensitiveKey(key)) {
      return '<redacted>';
    }
    if (depth >= maxDepth &&
        (value is Map<String, Object?> || value is List<Object?>)) {
      return '<max-depth>';
    }
    return switch (value) {
      null || bool() || int() || double() => value,
      String text =>
        text.length <= maxStringLength ? text : '<truncated:${text.length}>',
      Map<String, Object?> object => _redactObject(object, depth: depth),
      List<Object?> values => _redactList(values, depth: depth),
      _ => '<non-json:${value.runtimeType}>',
    };
  }

  List<Object?> _redactList(
    List<Object?> values, {
    required int depth,
  }) {
    if (depth >= maxDepth) {
      return const <Object?>['<max-depth>'];
    }
    return <Object?>[
      for (final value in values.take(maxCollectionEntries))
        _redactValue('', value, depth: depth + 1),
      if (values.length > maxCollectionEntries)
        '<truncated:${values.length - maxCollectionEntries}>',
    ];
  }
}

bool _isSensitiveKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.contains('secret') ||
      normalized.contains('token') ||
      normalized.contains('password') ||
      normalized.contains('authorization') ||
      normalized == 'environment' ||
      normalized == 'env' ||
      normalized.contains('workspacecontent') ||
      normalized == 'content' ||
      normalized == 'filecontents' ||
      normalized == 'text';
}
