import '../common/availability.dart';
import '../common/source_identity.dart';
import 'generated/inventory.g.dart';

const vmServiceMinimumRuntimeVersion = VmServiceWireVersion(4, 16);
const vmServiceCurrentRuntimeVersion = VmServiceWireVersion(4, 21);

const vmServiceVersionPolicy = VmServiceVersionPolicy(
  supportedMajor: 4,
  minimumMinor: 16,
  currentMinor: 21,
);

const vmServiceMinimumSourceIdentity = VmServiceSourceIdentity(
  sourceRelease: vmServiceGeneratedMinimumRelease,
  sourceRevision: vmServiceGeneratedMinimumRevision,
  artifactSha256: vmServiceGeneratedMinimumDocumentSha256,
  wireVersion: vmServiceMinimumRuntimeVersion,
);

const vmServiceCurrentSourceIdentity = VmServiceSourceIdentity(
  sourceRelease: vmServiceGeneratedCurrentRelease,
  sourceRevision: vmServiceGeneratedCurrentRevision,
  artifactSha256: vmServiceGeneratedCurrentDocumentSha256,
  wireVersion: vmServiceCurrentRuntimeVersion,
);

const vmServiceMinimumGeneratedArtifactSha256 =
    vmServiceGeneratedMinimumApiSha256;
const vmServiceCurrentGeneratedArtifactSha256 =
    vmServiceGeneratedCurrentApiSha256;
const vmServiceMinimumRuntimeOracleSha256 =
    vmServiceGeneratedMinimumOracleSha256;
const vmServiceCurrentRuntimeOracleSha256 =
    vmServiceGeneratedCurrentOracleSha256;

const vmServiceMinimumDocumentTitleVersion = '4.16';
const vmServiceMinimumDocumentDescriptionVersion = '4.16';
const vmServiceMinimumHasDocumentVersionMismatch = false;
const vmServiceCurrentDocumentTitleVersion = '4.21';
const vmServiceCurrentDocumentDescriptionVersion = '4.20';
const vmServiceCurrentHasDocumentVersionMismatch = true;
