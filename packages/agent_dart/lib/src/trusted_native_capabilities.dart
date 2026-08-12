// ignore: implementation_imports
import 'package:pigcode_ai_agent/src/driver/native_driver_capabilities.dart';
import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';

NativeDriverCapabilities bindProductionNativeCapabilities(
  SandboxCapabilityReport report,
) {
  report.requireProductionReady();
  return issueProductionNativeDriverCapabilities(
    manifestIdentity: 'phase-4-native-containment',
    manifestVersion: 1,
    sandboxCapabilityDigest: report.digest,
  );
}
