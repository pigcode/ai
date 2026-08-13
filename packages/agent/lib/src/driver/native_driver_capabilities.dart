import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class NativeDriverCapabilities {
  NativeDriverCapabilities._({
    required Map<String, EffectControl> toolEffects,
    required this.maximumPayloadBytes,
    required this.productionTrusted,
    required this.manifestIdentity,
    required this.manifestVersion,
    required this.sandboxCapabilityDigest,
  }) : _toolEffects = Map<String, EffectControl>.unmodifiable(toolEffects);

  factory NativeDriverCapabilities.unsafeDev({
    required Map<String, EffectControl> toolEffects,
    int maximumPayloadBytes = 64 * 1024,
  }) =>
      NativeDriverCapabilities._(
        toolEffects: toolEffects,
        maximumPayloadBytes: maximumPayloadBytes,
        productionTrusted: false,
        manifestIdentity: 'unsafe/dev-only',
        manifestVersion: 0,
        sandboxCapabilityDigest: null,
      );

  final Map<String, EffectControl> _toolEffects;
  final int maximumPayloadBytes;
  final bool productionTrusted;
  final String manifestIdentity;
  final int manifestVersion;
  final String? sandboxCapabilityDigest;

  DriverCapabilitySnapshot get snapshot => DriverCapabilitySnapshot(
        capabilities: <String>{
          'nativeToolLoop',
          if (productionTrusted) ...<String>{
            'sandboxEnforced',
            'trustedCapabilityRegistry',
          },
        },
        eventKinds: DriverEventKind.values.toSet(),
        maximumPayloadBytes: maximumPayloadBytes,
      );

  EffectControl effectFor(String toolIdentity) {
    final effect = _toolEffects[toolIdentity];
    if (effect != null) return effect;
    if (productionTrusted) {
      throw ArgumentError.value(
        toolIdentity,
        'toolIdentity',
        'unregistered production tool identity',
      );
    }
    return EffectControl.unknown;
  }

  void verifySandboxCapabilityDigest(String actualDigest) {
    if (!productionTrusted ||
        sandboxCapabilityDigest == null ||
        actualDigest != sandboxCapabilityDigest) {
      throw StateError('sandbox-capability-digest-mismatch');
    }
  }
}

NativeDriverCapabilities issueProductionNativeDriverCapabilities({
  required String manifestIdentity,
  required int manifestVersion,
  required String sandboxCapabilityDigest,
  int maximumPayloadBytes = 64 * 1024,
}) {
  if (manifestIdentity != 'phase-4-native-containment' ||
      manifestVersion != 1) {
    throw const FormatException('native-capability-manifest-identity-invalid');
  }
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(sandboxCapabilityDigest)) {
    throw const FormatException('sandbox-capability-digest-invalid');
  }
  return NativeDriverCapabilities._(
    toolEffects: const <String, EffectControl>{
      'host.file.write': EffectControl.managed,
      'host.process': EffectControl.managed,
      'host.network': EffectControl.managed,
      'dap.runInTerminal': EffectControl.interceptable,
      'lsp.workspace.applyEdit': EffectControl.interceptable,
      'external.shell': EffectControl.observedOnly,
      'unclassified': EffectControl.unknown,
    },
    maximumPayloadBytes: maximumPayloadBytes,
    productionTrusted: true,
    manifestIdentity: manifestIdentity,
    manifestVersion: manifestVersion,
    sandboxCapabilityDigest: sandboxCapabilityDigest,
  );
}
