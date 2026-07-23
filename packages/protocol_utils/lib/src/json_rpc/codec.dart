import 'dart:convert';

import '../errors.dart';
import '../json_value.dart';
import 'id.dart';
import 'message.dart';

/// Strict, non-batch JSON-RPC 2.0 envelope codec.
final class JsonRpcCodec {
  const JsonRpcCodec();

  /// Decodes a UTF-16 Dart string containing one JSON-RPC message.
  JsonRpcMessage decode(String source) {
    late final Object? decoded;
    try {
      _DuplicateKeyScanner(source).validate();
      decoded = jsonDecode(source);
    } on JsonRpcException {
      rethrow;
    } on FormatException catch (error) {
      throw JsonRpcException(
        'json_rpc_malformed_json',
        'Input is not valid JSON.',
        cause: error,
      );
    }
    return decodeValue(decoded);
  }

  /// Validates and decodes one already-parsed JSON-RPC message.
  JsonRpcMessage decodeValue(Object? value) {
    late final Object? frozen;
    try {
      frozen = freezeJsonValue(value);
    } on JsonValueException catch (error) {
      throw JsonRpcException(
        'json_rpc_invalid_json_value',
        'JSON-RPC envelope contains an invalid JSON value.',
        cause: error,
      );
    }

    if (frozen is List<Object?>) {
      throw const JsonRpcException(
        'json_rpc_batch_unsupported',
        'JSON-RPC batch messages are not supported.',
      );
    }
    if (frozen is! Map<String, Object?>) {
      throw const JsonRpcException(
        'json_rpc_invalid_envelope',
        'JSON-RPC message must be an object.',
      );
    }
    if (frozen['jsonrpc'] != '2.0') {
      throw const JsonRpcException(
        'json_rpc_invalid_version',
        'JSON-RPC version must be exactly "2.0".',
      );
    }

    final hasMethod = frozen.containsKey('method');
    final hasId = frozen.containsKey('id');
    final hasResult = frozen.containsKey('result');
    final hasError = frozen.containsKey('error');

    if (hasMethod) {
      if (hasResult || hasError) {
        throw const JsonRpcException(
          'json_rpc_invalid_envelope',
          'JSON-RPC call cannot contain result or error.',
        );
      }
      final method = frozen['method'];
      if (method is! String || method.isEmpty) {
        throw const JsonRpcException(
          'json_rpc_invalid_method',
          'JSON-RPC method must be a non-empty string.',
        );
      }
      final params = _decodeParams(frozen);
      if (hasId) {
        return JsonRpcRequest(
          id: JsonRpcId.fromJson(frozen['id']),
          method: method,
          params: params,
          extensions: _extensions(
            frozen,
            const <String>{'jsonrpc', 'id', 'method', 'params'},
          ),
        );
      }
      return JsonRpcNotification(
        method: method,
        params: params,
        extensions: _extensions(
          frozen,
          const <String>{'jsonrpc', 'method', 'params'},
        ),
      );
    }

    if (!hasId || (!hasResult && !hasError)) {
      throw const JsonRpcException(
        'json_rpc_invalid_envelope',
        'JSON-RPC response requires id and exactly one result or error.',
      );
    }
    if (hasResult && hasError) {
      throw const JsonRpcException(
        'json_rpc_ambiguous_response',
        'JSON-RPC response cannot contain both result and error.',
      );
    }

    final id = JsonRpcId.fromJson(frozen['id']);
    final extensions = _extensions(
      frozen,
      hasResult
          ? const <String>{'jsonrpc', 'id', 'result'}
          : const <String>{'jsonrpc', 'id', 'error'},
    );
    if (hasResult) {
      return JsonRpcSuccessResponse(
        id: id,
        result: frozen['result'],
        extensions: extensions,
      );
    }
    return JsonRpcErrorResponse(
      id: id,
      error: _decodeError(frozen['error']),
      extensions: extensions,
    );
  }

  /// Encodes one validated message as compact JSON.
  String encode(JsonRpcMessage message) =>
      jsonEncode(_canonicalize(message.toJson()));
}

JsonValue _decodeParams(JsonObject envelope) {
  if (!envelope.containsKey('params')) {
    return null;
  }
  final params = envelope['params'];
  if (params is! Map<String, Object?> && params is! List<Object?>) {
    throw const JsonRpcException(
      'json_rpc_invalid_params',
      'JSON-RPC params must be an object or array.',
    );
  }
  return params;
}

JsonRpcError _decodeError(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const JsonRpcException(
      'json_rpc_invalid_error',
      'JSON-RPC error must be an object.',
    );
  }
  final code = value['code'];
  final message = value['message'];
  if (code is! int || message is! String) {
    throw const JsonRpcException(
      'json_rpc_invalid_error',
      'JSON-RPC error requires an integer code and string message.',
    );
  }
  final extensions = _extensions(
    value,
    const <String>{'code', 'message', 'data'},
  );
  if (value.containsKey('data')) {
    return JsonRpcError(
      code: code,
      message: message,
      data: value['data'],
      extensions: extensions,
    );
  }
  return JsonRpcError(
    code: code,
    message: message,
    extensions: extensions,
  );
}

JsonObject _extensions(JsonObject value, Set<String> knownNames) =>
    freezeJsonObject(<String, Object?>{
      for (final entry in value.entries)
        if (!knownNames.contains(entry.key)) entry.key: entry.value,
    });

Object? _canonicalize(Object? value) {
  if (value is List<Object?>) {
    return <Object?>[
      for (final item in value) _canonicalize(item),
    ];
  }
  if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort();
    return <String, Object?>{
      for (final key in keys) key: _canonicalize(value[key]),
    };
  }
  return value;
}

final class _DuplicateKeyScanner {
  _DuplicateKeyScanner(this.source);

  final String source;
  int _index = 0;

  void validate() {
    _skipWhitespace();
    _parseValue();
    _skipWhitespace();
    if (_index != source.length) {
      throw const FormatException('Unexpected trailing JSON input.');
    }
  }

  void _parseValue() {
    if (_index >= source.length) {
      throw const FormatException('Unexpected end of JSON input.');
    }
    switch (source.codeUnitAt(_index)) {
      case 0x7b:
        _parseObject();
      case 0x5b:
        _parseArray();
      case 0x22:
        _parseString();
      case 0x74:
        _consumeLiteral('true');
      case 0x66:
        _consumeLiteral('false');
      case 0x6e:
        _consumeLiteral('null');
      default:
        _parseNumber();
    }
  }

  void _parseObject() {
    _expect(0x7b);
    _skipWhitespace();
    if (_consumeIf(0x7d)) {
      return;
    }
    final keys = <String>{};
    while (true) {
      if (_index >= source.length || source.codeUnitAt(_index) != 0x22) {
        throw const FormatException('JSON object key must be a string.');
      }
      final key = _parseString();
      if (!keys.add(key)) {
        throw const JsonRpcException(
          'json_rpc_duplicate_key',
          'JSON objects cannot contain duplicate keys.',
        );
      }
      _skipWhitespace();
      _expect(0x3a);
      _skipWhitespace();
      _parseValue();
      _skipWhitespace();
      if (_consumeIf(0x7d)) {
        return;
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  void _parseArray() {
    _expect(0x5b);
    _skipWhitespace();
    if (_consumeIf(0x5d)) {
      return;
    }
    while (true) {
      _parseValue();
      _skipWhitespace();
      if (_consumeIf(0x5d)) {
        return;
      }
      _expect(0x2c);
      _skipWhitespace();
    }
  }

  String _parseString() {
    final start = _index;
    _expect(0x22);
    while (_index < source.length) {
      final codeUnit = source.codeUnitAt(_index++);
      if (codeUnit == 0x22) {
        return jsonDecode(source.substring(start, _index)) as String;
      }
      if (codeUnit < 0x20) {
        throw const FormatException('Unescaped control character in string.');
      }
      if (codeUnit == 0x5c) {
        if (_index >= source.length) {
          throw const FormatException('Truncated JSON string escape.');
        }
        final escape = source.codeUnitAt(_index++);
        if (escape == 0x75) {
          for (var count = 0; count < 4; count += 1) {
            if (_index >= source.length ||
                !_isHex(source.codeUnitAt(_index++))) {
              throw const FormatException('Invalid JSON unicode escape.');
            }
          }
        } else if (!_simpleEscapes.contains(escape)) {
          throw const FormatException('Invalid JSON string escape.');
        }
      }
    }
    throw const FormatException('Unterminated JSON string.');
  }

  void _parseNumber() {
    final remainder = source.substring(_index);
    final match = _numberPattern.firstMatch(remainder);
    if (match == null) {
      throw const FormatException('Invalid JSON value.');
    }
    _index += match.group(0)!.length;
  }

  void _consumeLiteral(String literal) {
    if (!source.startsWith(literal, _index)) {
      throw const FormatException('Invalid JSON literal.');
    }
    _index += literal.length;
  }

  void _skipWhitespace() {
    while (_index < source.length) {
      final codeUnit = source.codeUnitAt(_index);
      if (codeUnit != 0x20 &&
          codeUnit != 0x09 &&
          codeUnit != 0x0a &&
          codeUnit != 0x0d) {
        return;
      }
      _index += 1;
    }
  }

  bool _consumeIf(int codeUnit) {
    if (_index < source.length && source.codeUnitAt(_index) == codeUnit) {
      _index += 1;
      return true;
    }
    return false;
  }

  void _expect(int codeUnit) {
    if (!_consumeIf(codeUnit)) {
      throw const FormatException('Unexpected JSON token.');
    }
  }
}

const _simpleEscapes = <int>{
  0x22,
  0x5c,
  0x2f,
  0x62,
  0x66,
  0x6e,
  0x72,
  0x74,
};

final _numberPattern = RegExp(
  r'^-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
);

bool _isHex(int codeUnit) =>
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    (codeUnit >= 0x41 && codeUnit <= 0x46) ||
    (codeUnit >= 0x61 && codeUnit <= 0x66);
