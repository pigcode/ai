import 'dart:collection';

const _maximumSafeInteger = 9007199254740991;

enum DomainJsonErrorCode {
  cycle,
  nonFiniteNumber,
  nonStringKey,
  unsupportedValue,
  unsafeInteger,
  loneSurrogate,
  depthLimit,
  collectionLimit,
  stringLimit,
  nodeLimit,
}

final class DomainJsonException extends FormatException {
  DomainJsonException(this.code, String message) : super(message);

  final DomainJsonErrorCode code;
}

final class DomainJsonLimits {
  const DomainJsonLimits({
    this.maxDepth = 64,
    this.maxCollectionLength = 10000,
    this.maxStringCodeUnits = 1024 * 1024,
    this.maxTotalNodes = 100000,
  })  : assert(maxDepth >= 0),
        assert(maxCollectionLength >= 0),
        assert(maxStringCodeUnits >= 0),
        assert(maxTotalNodes > 0);

  final int maxDepth;
  final int maxCollectionLength;
  final int maxStringCodeUnits;
  final int maxTotalNodes;
}

/// Marks an explicitly binary64 JSON number whose value may look integral on
/// JavaScript runtimes.
///
/// This is not an escape hatch for exact integers outside the safe range;
/// schemas must represent those as typed strings.
final class DomainJsonBinary64 {
  DomainJsonBinary64(double value) : value = _requireFinite(value);

  final double value;
}

/// Validates, detaches, and freezes values accepted by persisted domain JSON.
abstract final class DomainJson {
  static Object? freeze(
    Object? value, {
    DomainJsonLimits limits = const DomainJsonLimits(),
  }) {
    return _DomainJsonFreezer(limits).freeze(value);
  }
}

final class _DomainJsonFreezer {
  _DomainJsonFreezer(this.limits);

  final DomainJsonLimits limits;
  final Set<Object> _activeContainers = HashSet<Object>.identity();
  var _nodes = 0;

  Object? freeze(Object? value, [int depth = 0]) {
    _nodes += 1;
    if (_nodes > limits.maxTotalNodes) {
      throw DomainJsonException(
        DomainJsonErrorCode.nodeLimit,
        'Domain JSON exceeds the total-node limit.',
      );
    }
    if (depth > limits.maxDepth) {
      throw DomainJsonException(
        DomainJsonErrorCode.depthLimit,
        'Domain JSON exceeds the depth limit.',
      );
    }

    if (value == null || value is bool) {
      return value;
    }
    if (value is String) {
      _validateString(value);
      return value;
    }
    if (value is DomainJsonBinary64) {
      return value;
    }
    if (value is int) {
      if (value < -_maximumSafeInteger || value > _maximumSafeInteger) {
        throw DomainJsonException(
          DomainJsonErrorCode.unsafeInteger,
          'Integers outside the binary64 safe range require a typed string.',
        );
      }
      return value == 0 ? 0 : value;
    }
    if (value is double) {
      if (!value.isFinite) {
        throw DomainJsonException(
          DomainJsonErrorCode.nonFiniteNumber,
          'Domain JSON numbers must be finite.',
        );
      }
      return value;
    }
    if (value is List<Object?>) {
      return _freezeList(value, depth);
    }
    if (value is Map<Object?, Object?>) {
      return _freezeMap(value, depth);
    }
    throw DomainJsonException(
      DomainJsonErrorCode.unsupportedValue,
      'Unsupported domain JSON value of type ${value.runtimeType}.',
    );
  }

  List<Object?> _freezeList(List<Object?> value, int depth) {
    _checkCollection(value, value.length);
    try {
      return List<Object?>.unmodifiable(
        value.map((item) => freeze(item, depth + 1)),
      );
    } finally {
      _activeContainers.remove(value);
    }
  }

  Map<String, Object?> _freezeMap(Map<Object?, Object?> value, int depth) {
    _checkCollection(value, value.length);
    try {
      final result = <String, Object?>{};
      for (final entry in value.entries) {
        final key = entry.key;
        if (key is! String) {
          throw DomainJsonException(
            DomainJsonErrorCode.nonStringKey,
            'Domain JSON object keys must be strings.',
          );
        }
        _validateString(key);
        result[key] = freeze(entry.value, depth + 1);
      }
      return Map<String, Object?>.unmodifiable(result);
    } finally {
      _activeContainers.remove(value);
    }
  }

  void _checkCollection(Object value, int length) {
    if (!_activeContainers.add(value)) {
      throw DomainJsonException(
        DomainJsonErrorCode.cycle,
        'Domain JSON must not contain cycles.',
      );
    }
    if (length > limits.maxCollectionLength) {
      _activeContainers.remove(value);
      throw DomainJsonException(
        DomainJsonErrorCode.collectionLimit,
        'Domain JSON collection exceeds the length limit.',
      );
    }
  }

  void _validateString(String value) {
    if (value.length > limits.maxStringCodeUnits) {
      throw DomainJsonException(
        DomainJsonErrorCode.stringLimit,
        'Domain JSON string exceeds the code-unit limit.',
      );
    }
    for (var index = 0; index < value.length; index += 1) {
      final codeUnit = value.codeUnitAt(index);
      if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
        if (index + 1 >= value.length) {
          _throwLoneSurrogate();
        }
        final next = value.codeUnitAt(index + 1);
        if (next < 0xdc00 || next > 0xdfff) {
          _throwLoneSurrogate();
        }
        index += 1;
      } else if (codeUnit >= 0xdc00 && codeUnit <= 0xdfff) {
        _throwLoneSurrogate();
      }
    }
  }

  Never _throwLoneSurrogate() {
    throw DomainJsonException(
      DomainJsonErrorCode.loneSurrogate,
      'Domain JSON strings must not contain lone UTF-16 surrogates.',
    );
  }
}

double _requireFinite(double value) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, 'value', 'Must be finite.');
  }
  return value;
}
