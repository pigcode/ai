import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

provider.Headers? mergeHeaders(
  provider.Headers? base,
  provider.Headers? overrides,
) {
  if (base == null && overrides == null) {
    return null;
  }

  return Map<String, String>.unmodifiable({
    if (base != null) ...base,
    if (overrides != null) ...overrides,
  });
}

provider.ProviderOptions? mergeProviderOptionsDeep(
  provider.ProviderOptions? base,
  provider.ProviderOptions? overrides,
) {
  if (base == null && overrides == null) {
    return null;
  }

  final merged = <String, provider.JsonObject>{};
  if (base != null) {
    for (final entry in base.entries) {
      merged[entry.key] = snapshotJsonObject(entry.value);
    }
  }
  if (overrides != null) {
    for (final entry in overrides.entries) {
      merged[entry.key] = mergeJsonObjects(merged[entry.key], entry.value);
    }
  }

  return Map<String, provider.JsonObject>.unmodifiable(merged);
}

provider.JsonObject mergeJsonObjects(
  provider.JsonObject? base,
  provider.JsonObject overrides,
) {
  if (base == null) {
    return snapshotJsonObject(overrides);
  }

  final merged = <String, Object?>{
    for (final entry in base.entries) entry.key: snapshotJsonValue(entry.value),
  };
  for (final entry in overrides.entries) {
    final baseValue = merged[entry.key];
    final overrideValue = entry.value;
    if (_isJsonObject(baseValue) && _isJsonObject(overrideValue)) {
      merged[entry.key] = mergeJsonObjects(
        _asJsonObject(baseValue as Map<Object?, Object?>),
        _asJsonObject(overrideValue as Map<Object?, Object?>),
      );
    } else {
      merged[entry.key] = snapshotJsonValue(overrideValue);
    }
  }

  return Map<String, Object?>.unmodifiable(merged);
}

provider.JsonObject snapshotJsonObject(provider.JsonObject value) {
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry(key, snapshotJsonValue(value))),
  );
}

Object? snapshotJsonValue(Object? value) {
  if (_isJsonObject(value)) {
    return snapshotJsonObject(_asJsonObject(value as Map<Object?, Object?>));
  }
  if (value is List) {
    return List<Object?>.unmodifiable(value.map(snapshotJsonValue));
  }
  return value;
}

bool _isJsonObject(Object? value) {
  return value is Map<Object?, Object?> &&
      value.keys.every((key) => key is String);
}

provider.JsonObject _asJsonObject(Map<Object?, Object?> value) {
  return value.map(
    (key, value) => MapEntry(key as String, snapshotJsonValue(value)),
  );
}
