import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  test('portable barrel exposes the fixed stable ACP identity', () {
    expect(acpProtocolVersion, 1);
    expect(acpSchemaRelease, 'schema-v1.20.0');
    expect(acpSchemaSha256, hasLength(64));
  });
}
