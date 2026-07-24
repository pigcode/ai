import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'domain_json.dart';

String canonicalJsonEncode(
  Object? value, {
  DomainJsonLimits limits = const DomainJsonLimits(),
}) {
  final frozen = DomainJson.freeze(value, limits: limits);
  final output = StringBuffer();
  _writeCanonicalJson(output, frozen);
  return output.toString();
}

Uint8List canonicalJsonBytes(
  Object? value, {
  DomainJsonLimits limits = const DomainJsonLimits(),
}) =>
    Uint8List.fromList(utf8.encode(canonicalJsonEncode(value, limits: limits)));

String canonicalJsonSha256(
  Object? value, {
  DomainJsonLimits limits = const DomainJsonLimits(),
}) =>
    sha256.convert(canonicalJsonBytes(value, limits: limits)).toString();

void _writeCanonicalJson(StringBuffer output, Object? value) {
  if (value == null) {
    output.write('null');
  } else if (value is bool) {
    output.write(value ? 'true' : 'false');
  } else if (value is DomainJsonBinary64) {
    output.write(_canonicalDouble(value.value));
  } else if (value is int) {
    output.write(value);
  } else if (value is double) {
    output.write(_canonicalDouble(value));
  } else if (value is String) {
    _writeString(output, value);
  } else if (value is List<Object?>) {
    output.write('[');
    for (var index = 0; index < value.length; index += 1) {
      if (index != 0) {
        output.write(',');
      }
      _writeCanonicalJson(output, value[index]);
    }
    output.write(']');
  } else if (value is Map<String, Object?>) {
    final keys = value.keys.toList()..sort(_compareUtf16);
    output.write('{');
    for (var index = 0; index < keys.length; index += 1) {
      if (index != 0) {
        output.write(',');
      }
      final key = keys[index];
      _writeString(output, key);
      output.write(':');
      _writeCanonicalJson(output, value[key]);
    }
    output.write('}');
  } else {
    throw StateError('DomainJson.freeze returned ${value.runtimeType}.');
  }
}

String _canonicalDouble(double value) {
  if (value == 0) {
    return '0';
  }
  final raw = value.toString().toLowerCase();
  final exponentIndex = raw.indexOf('e');
  if (exponentIndex < 0) {
    return raw.endsWith('.0') ? raw.substring(0, raw.length - 2) : raw;
  }

  var mantissa = raw.substring(0, exponentIndex);
  if (mantissa.endsWith('.0')) {
    mantissa = mantissa.substring(0, mantissa.length - 2);
  }
  final exponent = int.parse(raw.substring(exponentIndex + 1));
  return '$mantissa'
      'e${exponent >= 0 ? '+' : ''}$exponent';
}

int _compareUtf16(String left, String right) {
  final commonLength = left.length < right.length ? left.length : right.length;
  for (var index = 0; index < commonLength; index += 1) {
    final comparison = left.codeUnitAt(index) - right.codeUnitAt(index);
    if (comparison != 0) {
      return comparison;
    }
  }
  return left.length - right.length;
}

void _writeString(StringBuffer output, String value) {
  output.write('"');
  for (var index = 0; index < value.length; index += 1) {
    final codeUnit = value.codeUnitAt(index);
    switch (codeUnit) {
      case 0x08:
        output.write(r'\b');
      case 0x09:
        output.write(r'\t');
      case 0x0a:
        output.write(r'\n');
      case 0x0c:
        output.write(r'\f');
      case 0x0d:
        output.write(r'\r');
      case 0x22:
        output.write(r'\"');
      case 0x5c:
        output.write(r'\\');
      default:
        if (codeUnit <= 0x1f) {
          output
            ..write(r'\u')
            ..write(codeUnit.toRadixString(16).padLeft(4, '0'));
        } else if (codeUnit >= 0xd800 && codeUnit <= 0xdbff) {
          output.write(value.substring(index, index + 2));
          index += 1;
        } else {
          output.writeCharCode(codeUnit);
        }
    }
  }
  output.write('"');
}
