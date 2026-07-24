import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('exposes the exact DAP 1.71.0 source identity', () {
    expect(dapSpecificationVersion, '1.71.0');
    expect(dapSourceRelease, 'v1.71.0');
    expect(dapSourceRevision, hasLength(40));
    expect(dapSchemaSha256, hasLength(64));
    expect(dapSchemaDialect, 'http://json-schema.org/draft-04/schema#');
  });
}
