import 'availability.dart';

/// The three independent protocol surfaces shipped by this package.
enum DartToolingProtocol {
  analysisServer,
  dtd,
  vmService,
}

/// Auditable identity shared by pinned Dart tooling protocol sources.
abstract interface class ProtocolSourceIdentity {
  DartToolingProtocol get protocol;
  String get sourceRelease;
  String get sourceRevision;
  String get artifactSha256;
}

/// Identity of one Analysis Server protocol source snapshot.
final class AnalysisServerSourceIdentity implements ProtocolSourceIdentity {
  const AnalysisServerSourceIdentity({
    required this.sourceRelease,
    required this.sourceRevision,
    required this.artifactSha256,
    required this.apiVersion,
  });

  @override
  DartToolingProtocol get protocol => DartToolingProtocol.analysisServer;

  @override
  final String sourceRelease;

  @override
  final String sourceRevision;

  @override
  final String artifactSha256;

  final AnalysisServerApiVersion apiVersion;
}

/// Identity of one DTD inventory snapshot.
///
/// DTD intentionally has no wire-version field. Its contract is the pinned
/// method inventory identified by [inventoryRevision].
final class DtdSourceIdentity implements ProtocolSourceIdentity {
  const DtdSourceIdentity({
    required this.sourceRelease,
    required this.sourceRevision,
    required this.artifactSha256,
    required this.inventoryRevision,
  });

  @override
  DartToolingProtocol get protocol => DartToolingProtocol.dtd;

  @override
  final String sourceRelease;

  @override
  final String sourceRevision;

  @override
  final String artifactSha256;

  final String inventoryRevision;
}

/// Identity of one VM Service protocol source snapshot.
final class VmServiceSourceIdentity implements ProtocolSourceIdentity {
  const VmServiceSourceIdentity({
    required this.sourceRelease,
    required this.sourceRevision,
    required this.artifactSha256,
    required this.wireVersion,
  });

  @override
  DartToolingProtocol get protocol => DartToolingProtocol.vmService;

  @override
  final String sourceRelease;

  @override
  final String sourceRevision;

  @override
  final String artifactSha256;

  final VmServiceWireVersion wireVersion;
}
