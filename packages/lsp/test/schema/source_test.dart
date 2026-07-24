import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('exposes the exact LSP audit-snapshot source identity', () {
    expect(lspSpecificationVersion, '3.18.0');
    expect(lspSourceRelease, '3.18-audit-snapshot');
    expect(lspSourceRevision, hasLength(40));
    expect(lspMetaModelSha256, hasLength(64));
    expect(lspSchemaDialect, 'http://json-schema.org/draft-07/schema#');
  });
}
