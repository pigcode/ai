import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  test('embeds only the fixed ACP stable-v1 source', () {
    expect(acpSchemaRelease, 'schema-v1.20.0');
    expect(acpSchemaSha256,
        '92c1dfcda10dd47e99127500a3763da2b471f9ac61e12b9bf0430c32cf953796');
    expect(AcpSchema.instance.document[r'$schema'],
        'https://json-schema.org/draft/2020-12/schema');
    expect(AcpSchema.instance.definitionNames, hasLength(142));
    expect(
      AcpSchema.instance.document.toString(),
      isNot(anyOf(contains('unstable'), contains('ProtocolLevelV2'))),
    );
  });
}
