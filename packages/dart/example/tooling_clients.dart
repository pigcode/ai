import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:pigcode_ai_dart/pigcode_ai_dart_vm_service.dart';

void main() {
  final analysisServer = AnalysisServerClient();
  final analysisVersion = analysisServer.beginVersionQuery();
  analysisServer.completeVersionQuery(
    analysisVersion.id,
    const <String, Object?>{'version': '1.40.1'},
  );

  final dtd = DtdClient();
  final dtdListen = dtd.streams.listen('Editor');

  final vmService = VmServiceConnection();
  final vmVersion = vmService.beginVersionQuery();
  vmService.completeVersionQuery(
    vmVersion.id,
    const <String, Object?>{'type': 'Version', 'major': 4, 'minor': 21},
  );
  final protocols = vmService.beginSupportedProtocolsQuery();
  vmService.completeSupportedProtocolsQuery(
    protocols.id,
    const <String, Object?>{
      'type': 'ProtocolList',
      'protocols': <Object?>[
        <String, Object?>{
          'protocolName': 'VM Service',
          'major': 4,
          'minor': 21,
        },
      ],
    },
  );

  // These request records are ready for caller-owned transports.
  print(
    '${analysisServer.connection.capabilities.apiVersion}; '
    '${dtdListen.method}; ${vmService.capabilities.wireVersion}',
  );
}
