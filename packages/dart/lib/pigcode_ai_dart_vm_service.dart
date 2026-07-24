/// Portable VM Service protocol surface.
library;

export 'src/common/availability.dart'
    show VmServiceVersionPolicy, VmServiceWireVersion;
export 'src/common/diagnostics.dart';
export 'src/common/errors.dart';
export 'src/common/source_identity.dart'
    show DartToolingProtocol, ProtocolSourceIdentity, VmServiceSourceIdentity;
export 'src/vm_service/capabilities.dart';
export 'src/vm_service/client.dart';
export 'src/vm_service/codec.dart';
export 'src/vm_service/connection.dart';
export 'src/vm_service/generated/models.g.dart';
export 'src/vm_service/models.dart';
export 'src/vm_service/references.dart';
export 'src/vm_service/streams.dart';
export 'src/vm_service/version.dart';
