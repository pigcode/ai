import 'dart:typed_data';

import 'package:pigcode_ai_provider/src/shared/shared.dart';
import 'package:test/test.dart';

void main() {
  group('Warning equality', () {
    test('UnsupportedWarning equal by feature and details', () {
      expect(
        const UnsupportedWarning('images', details: 'no vision'),
        equals(const UnsupportedWarning('images', details: 'no vision')),
      );
      expect(
        const UnsupportedWarning('images'),
        isNot(equals(const UnsupportedWarning('images', details: 'x'))),
      );
      expect(
        const UnsupportedWarning('images'),
        isNot(equals(const UnsupportedWarning('audio'))),
      );
    });

    test('CompatibilityWarning equal by feature and details', () {
      expect(
        const CompatibilityWarning('json', details: 'coerced'),
        equals(const CompatibilityWarning('json', details: 'coerced')),
      );
      expect(
        const CompatibilityWarning('json'),
        isNot(equals(const CompatibilityWarning('json', details: 'coerced'))),
      );
    });

    test('DeprecatedWarning equal by setting and message', () {
      expect(
        const DeprecatedWarning('topK', 'use topP'),
        equals(const DeprecatedWarning('topK', 'use topP')),
      );
      expect(
        const DeprecatedWarning('topK', 'use topP'),
        isNot(equals(const DeprecatedWarning('topK', 'removed'))),
      );
    });

    test('OtherWarning equal by message', () {
      expect(
        const OtherWarning('heads up'),
        equals(const OtherWarning('heads up')),
      );
      expect(
        const OtherWarning('heads up'),
        isNot(equals(const OtherWarning('something else'))),
      );
    });

    test('distinct Warning variants are unequal', () {
      expect(
        const UnsupportedWarning('x'),
        isNot(equals(const CompatibilityWarning('x'))),
      );
      expect(
        const OtherWarning('m'),
        isNot(equals(const DeprecatedWarning('s', 'm'))),
      );
    });
  });

  group('FileData equality', () {
    test('FileDataBytes deep-compares bytes', () {
      expect(
        FileDataBytes(Uint8List.fromList(<int>[1, 2, 3])),
        equals(FileDataBytes(Uint8List.fromList(<int>[1, 2, 3]))),
      );
      expect(
        FileDataBytes(Uint8List.fromList(<int>[1, 2, 3])),
        isNot(equals(FileDataBytes(Uint8List.fromList(<int>[1, 2, 4])))),
      );
    });

    test('FileDataBase64 equal by string', () {
      expect(
        const FileDataBase64('aGk='),
        equals(const FileDataBase64('aGk=')),
      );
      expect(
        const FileDataBase64('aGk='),
        isNot(equals(const FileDataBase64('Ynll'))),
      );
    });

    test('FileDataUrl equal by uri', () {
      expect(
        FileDataUrl(Uri.parse('https://example.com/a.png')),
        equals(FileDataUrl(Uri.parse('https://example.com/a.png'))),
      );
      expect(
        FileDataUrl(Uri.parse('https://example.com/a.png')),
        isNot(equals(FileDataUrl(Uri.parse('https://example.com/b.png')))),
      );
    });

    test('FileDataReference deep-compares reference map', () {
      expect(
        const FileDataReference(<String, String>{'openai': 'file-123'}),
        equals(const FileDataReference(<String, String>{'openai': 'file-123'})),
      );
      expect(
        const FileDataReference(<String, String>{'openai': 'file-123'}),
        isNot(equals(
          const FileDataReference(<String, String>{'openai': 'file-999'}),
        )),
      );
    });

    test('FileDataText equal by text', () {
      expect(
        const FileDataText('hello'),
        equals(const FileDataText('hello')),
      );
      expect(
        const FileDataText('hello'),
        isNot(equals(const FileDataText('world'))),
      );
    });

    test('distinct FileData variants are unequal', () {
      expect(
        const FileDataBase64('aGk='),
        isNot(equals(const FileDataText('aGk='))),
      );
      expect(
        FileDataUrl(Uri.parse('https://example.com/a.png')),
        isNot(equals(const FileDataText('https://example.com/a.png'))),
      );
    });

    test('OutputFileData is the bytes/base64/url subset (v7 output side)', () {
      // bytes/base64/url 属输出子集 OutputFileData。
      expect(const FileDataBase64('YQ=='), isA<OutputFileData>());
      expect(
        FileDataUrl(Uri.parse('https://example.com/a.png')),
        isA<OutputFileData>(),
      );
      // reference / text 仅输入侧:是 FileData,但不属输出子集。
      const ref = FileDataReference(<String, String>{'openai': 'f1'});
      expect(ref, isA<FileData>());
      expect(ref, isNot(isA<OutputFileData>()));
      expect(const FileDataText('x'), isA<FileData>());
      expect(const FileDataText('x'), isNot(isA<OutputFileData>()));
    });
  });
}
