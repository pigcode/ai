import 'dart:collection';

import 'errors.dart';

/// A JSON-compatible scalar, list, or string-keyed object.
///
/// The alias intentionally remains [Object?] because Dart has no recursive
/// type aliases. Use [freezeJsonValue] at every untrusted boundary.
typedef JsonValue = Object?;

/// A string-keyed JSON object.
typedef JsonObject = Map<String, Object?>;

/// A JSON array.
typedef JsonArray = List<Object?>;

const _maximumJsonDepth = 256;

/// Validates [value], deeply copies it, and freezes every collection.
JsonValue freezeJsonValue(Object? value) => _JsonFreezer().freeze(value);

/// Validates and freezes a JSON object.
JsonObject freezeJsonObject(Map<Object?, Object?> value) =>
    freezeJsonValue(value) as JsonObject;

/// Validates and freezes a JSON array.
JsonArray freezeJsonArray(List<Object?> value) =>
    freezeJsonValue(value) as JsonArray;

final class _JsonFreezer {
  final Set<Object> _activeCollections = HashSet<Object>.identity();

  Object? freeze(Object? value, {int depth = 0}) {
    if (depth > _maximumJsonDepth) {
      throw const JsonValueException(
        'json_depth_exceeded',
        'JSON value exceeds the maximum supported nesting depth.',
      );
    }
    if (value == null || value is bool || value is String || value is int) {
      return value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw const JsonValueException(
          'json_non_finite_number',
          'JSON numbers must be finite.',
        );
      }
      return value;
    }
    if (value is List<Object?>) {
      return _freezeCollection(
        value,
        () => List<Object?>.unmodifiable(
          value.map((item) => freeze(item, depth: depth + 1)),
        ),
      );
    }
    if (value is Map) {
      return _freezeCollection(value, () {
        final result = <String, Object?>{};
        for (final entry in value.entries) {
          final key = entry.key;
          if (key is! String) {
            throw const JsonValueException(
              'json_non_string_key',
              'JSON object keys must be strings.',
            );
          }
          result[key] = freeze(entry.value, depth: depth + 1);
        }
        return Map<String, Object?>.unmodifiable(result);
      });
    }
    if (value is num) {
      throw const JsonValueException(
        'json_unsupported_number',
        'JSON numbers must be represented by Dart int or finite double.',
      );
    }
    throw JsonValueException(
      'json_unsupported_type',
      'Unsupported JSON value type: ${value.runtimeType}.',
    );
  }

  T _freezeCollection<T>(Object source, T Function() copy) {
    if (!_activeCollections.add(source)) {
      throw const JsonValueException(
        'json_cycle',
        'JSON values cannot contain reference cycles.',
      );
    }
    try {
      return copy();
    } finally {
      _activeCollections.remove(source);
    }
  }
}
