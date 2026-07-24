import 'package:pigcode_ai_dart/pigcode_ai_dart.dart';
import 'package:test/test.dart';

void main() {
  test('protocol identities retain distinct version types', () {
    const analysisVersion = AnalysisServerApiVersion(1, 40, 1);
    const vmVersion = VmServiceWireVersion(4, 21);

    const analysis = AnalysisServerSourceIdentity(
      sourceRelease: '3.12.2',
      sourceRevision: 'analysis-revision',
      artifactSha256: 'analysis-sha256',
      apiVersion: analysisVersion,
    );
    const dtd = DtdSourceIdentity(
      sourceRelease: '3.12.2',
      sourceRevision: 'dtd-revision',
      artifactSha256: 'dtd-sha256',
      inventoryRevision: 'dtd-inventory-v1',
    );
    const vm = VmServiceSourceIdentity(
      sourceRelease: '3.12.2',
      sourceRevision: 'vm-revision',
      artifactSha256: 'vm-sha256',
      wireVersion: vmVersion,
    );

    expect(analysis.protocol, DartToolingProtocol.analysisServer);
    expect(dtd.protocol, DartToolingProtocol.dtd);
    expect(vm.protocol, DartToolingProtocol.vmService);
    expect(analysis.apiVersion, analysisVersion);
    expect(dtd.inventoryRevision, 'dtd-inventory-v1');
    expect(vm.wireVersion, vmVersion);
    expect(analysis.apiVersion.runtimeType, isNot(vm.wireVersion.runtimeType));
  });

  test('each protocol uses its own availability policy', () {
    final analysis = AnalysisServerVersionPolicy(
      minimum: AnalysisServerApiVersion(1, 38, 0),
      current: AnalysisServerApiVersion(1, 40, 1),
    );
    const dtd = DtdInventoryPolicy(
      inventoryRevision: 'dtd-inventory-v1',
    );
    const vm = VmServiceVersionPolicy(
      supportedMajor: 4,
      minimumMinor: 14,
      currentMinor: 21,
    );

    expect(analysis.supports(const AnalysisServerApiVersion(1, 39, 0)), isTrue);
    expect(analysis.supports(const AnalysisServerApiVersion(2, 0, 0)), isFalse);
    expect(dtd.accepts('dtd-inventory-v1'), isTrue);
    expect(dtd.accepts('4.21'), isFalse);
    expect(vm.supports(const VmServiceWireVersion(4, 20)), isTrue);
    expect(vm.supports(const VmServiceWireVersion(5, 0)), isFalse);
  });
}
