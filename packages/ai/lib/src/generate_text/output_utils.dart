import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

provider.JsonSchema freezeJsonSchema(provider.JsonSchema schema) {
  return provider.JsonSchema(_deepUnmodifiableObject(schema.value));
}

provider.JsonSchema arrayWrapperSchema(provider.JsonSchema element) {
  final itemSchema = Map<String, Object?>.from(element.value)
    ..remove(r'$schema');
  final definitions = itemSchema.remove(r'$defs');

  return provider.JsonSchema(_deepUnmodifiableObject(<String, Object?>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    if (definitions != null) r'$defs': definitions,
    'type': 'object',
    'properties': <String, Object?>{
      'elements': <String, Object?>{
        'type': 'array',
        'items': _deepUnmodifiable(itemSchema),
      },
    },
    'required': <Object?>['elements'],
    'additionalProperties': false,
  }));
}

provider.JsonSchema choiceWrapperSchema(List<String> options) {
  return provider.JsonSchema(_deepUnmodifiableObject(<String, Object?>{
    r'$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'properties': <String, Object?>{
      'result': <String, Object?>{
        'type': 'string',
        'enum': List<String>.unmodifiable(options),
      },
    },
    'required': <Object?>['result'],
    'additionalProperties': false,
  }));
}

bool jsonDeepEquals(Object? a, Object? b) {
  if (identical(a, b)) {
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!jsonDeepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !jsonDeepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

Map<String, Object?> _deepUnmodifiableObject(Map<String, Object?> value) {
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, _deepUnmodifiable(value))),
  );
}

Object? _deepUnmodifiable(Object? value) {
  if (value is Map<String, Object?>) {
    return _deepUnmodifiableObject(value);
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map(
        (key, value) => MapEntry(key as String, _deepUnmodifiable(value)),
      ),
    );
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(_deepUnmodifiable));
  }
  return value;
}
