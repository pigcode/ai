import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('DTD identities pin both SDK documents and one fixed inventory', () {
    expect(dtdInventoryRevision, 'dtd-fixed-inventory-v1');
    expect(dtdMinimumSourceIdentity.sourceRelease, '3.6.0');
    expect(dtdCurrentSourceIdentity.sourceRelease, '3.12.2');
    expect(dtdMinimumSourceIdentity.sourceRevision, hasLength(40));
    expect(dtdCurrentSourceIdentity.sourceRevision, hasLength(40));
    expect(dtdMinimumSourceIdentity.artifactSha256, hasLength(64));
    expect(dtdCurrentSourceIdentity.artifactSha256, hasLength(64));
    expect(dtdInventorySha256, hasLength(64));
  });
}
