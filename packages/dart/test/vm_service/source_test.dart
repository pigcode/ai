import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';
import 'package:test/test.dart';

void main() {
  test('VM Service identities pin docs, generated API, and runtime oracle', () {
    expect(vmServiceMinimumSourceIdentity.sourceRelease, '3.6.0');
    expect(vmServiceCurrentSourceIdentity.sourceRelease, '3.12.2');
    expect(
      vmServiceMinimumSourceIdentity.wireVersion,
      const VmServiceWireVersion(4, 16),
    );
    expect(
      vmServiceCurrentSourceIdentity.wireVersion,
      const VmServiceWireVersion(4, 21),
    );
    expect(vmServiceMinimumGeneratedArtifactSha256, hasLength(64));
    expect(vmServiceCurrentGeneratedArtifactSha256, hasLength(64));
    expect(vmServiceMinimumRuntimeOracleSha256, hasLength(64));
    expect(vmServiceCurrentRuntimeOracleSha256, hasLength(64));
  });
}
