import 'dart:typed_data';

Iterable<Uint8List> everyTruncatedPrefix(Uint8List bytes) sync* {
  for (var length = 0; length < bytes.length; length++) {
    yield Uint8List.sublistView(bytes, 0, length);
  }
}

Uint8List changedStoreByte(Uint8List bytes, int offset, int value) {
  final changed = Uint8List.fromList(bytes);
  changed[offset] = value;
  return changed;
}
