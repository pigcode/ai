import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

Uint8List storeSha256(List<int> bytes) =>
    Uint8List.fromList(sha256.convert(bytes).bytes);

Uint8List storeDomainDigest(String domain, Iterable<List<int>> parts) {
  final builder = BytesBuilder(copy: false)
    ..add(utf8.encode(domain))
    ..addByte(0);
  for (final part in parts) {
    builder.add(part);
  }
  return storeSha256(builder.takeBytes());
}

String storeHex(List<int> bytes) {
  final output = StringBuffer();
  for (final byte in bytes) {
    output.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return output.toString();
}

Uint8List storeDigestFromHex(String value) {
  if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(value)) {
    throw FormatException('Expected a lowercase SHA-256 digest.', value);
  }
  return Uint8List.fromList(<int>[
    for (var offset = 0; offset < value.length; offset += 2)
      int.parse(value.substring(offset, offset + 2), radix: 16),
  ]);
}

bool storeBytesEqual(List<int> left, List<int> right) {
  if (left.length != right.length) return false;
  var difference = 0;
  for (var index = 0; index < left.length; index++) {
    difference |= left[index] ^ right[index];
  }
  return difference == 0;
}

final class StoreDigestAccumulator {
  StoreDigestAccumulator._(Iterable<List<int>> prefix) {
    _input = sha256.startChunkedConversion(_output);
    for (final bytes in prefix) {
      _input.add(bytes);
    }
  }

  factory StoreDigestAccumulator.sha256() =>
      StoreDigestAccumulator._(const <List<int>>[]);

  factory StoreDigestAccumulator.domain(String domain) =>
      StoreDigestAccumulator._(<List<int>>[
        utf8.encode(domain),
        const <int>[0],
      ]);

  final _StoreDigestSink _output = _StoreDigestSink();
  late final ByteConversionSink _input;
  bool _closed = false;

  void add(List<int> bytes) {
    if (_closed) {
      throw StateError('Store digest accumulator is already closed.');
    }
    _input.add(bytes);
  }

  Uint8List close() {
    if (_closed) {
      throw StateError('Store digest accumulator is already closed.');
    }
    _closed = true;
    _input.close();
    return Uint8List.fromList(_output.value!.bytes);
  }
}

final class _StoreDigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) {
    if (value != null) {
      throw StateError('Store digest sink received multiple values.');
    }
    value = data;
  }

  @override
  void close() {}
}

Uint8List storeU16(int value) {
  final bytes = ByteData(2)..setUint16(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List storeU32(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List storeU64(int value) {
  final bytes = ByteData(8)..setUint64(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}
