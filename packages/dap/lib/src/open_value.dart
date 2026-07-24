import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Forward-compatible DAP value whose schema uses the nonstandard `_enum`.
final class DapOpenValue<T extends Object> {
  factory DapOpenValue(
    T value, {
    required Set<T> knownValues,
  }) {
    final frozen = freezeJsonValue(value);
    if (frozen is! T) {
      throw ArgumentError.value(value, 'value', 'Must be JSON-compatible.');
    }
    return DapOpenValue<T>._(
      frozen,
      Set<T>.unmodifiable(knownValues),
    );
  }

  const DapOpenValue._(this.value, this.knownValues);

  final T value;
  final Set<T> knownValues;

  bool get isKnown => knownValues.contains(value);

  T toJson() => value;
}
