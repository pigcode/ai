import 'dart:convert';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('rejects unknown methods', () {
    expect(
      () => LspCodec.instance.decode(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'unknown/method',
          'params': <String, Object?>{},
        }),
        sender: LspMessageSender.client,
      ),
      throwsA(
        isA<LspCodecException>().having(
          (error) => error.code,
          'code',
          'lsp_unknown_method',
        ),
      ),
    );
  });

  test('rejects a method from the wrong sender direction', () {
    expect(
      () => LspCodec.instance.decode(
        jsonEncode(<String, Object?>{
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'initialize',
          'params': <String, Object?>{},
        }),
        sender: LspMessageSender.server,
      ),
      throwsA(
        isA<LspCodecException>().having(
          (error) => error.code,
          'code',
          'lsp_wrong_direction',
        ),
      ),
    );
  });

  test('rejects missing required fields and invalid unions', () {
    expect(
      () => LspPosition.fromJson(<String, Object?>{}),
      throwsA(isA<LspSchemaException>()),
    );
    expect(
      () => LspDefinition.fromJson(42),
      throwsA(isA<LspSchemaException>()),
    );
  });

  test('rejects unknown values for closed enumerations', () {
    expect(
      () => LspTextDocumentSyncKind.fromJson(99),
      throwsA(
        isA<LspSchemaException>().having(
          (error) => error.code,
          'code',
          'lsp_closed_enum_unknown',
        ),
      ),
    );
  });
}
