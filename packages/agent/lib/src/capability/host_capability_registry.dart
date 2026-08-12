import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

enum HostCapabilityKind { file, process, pty, git }

final class HostCapabilityProposal {
  HostCapabilityProposal({
    required this.toolIdentity,
    required this.effectControl,
    required Map<String, Object?> arguments,
  }) : arguments = DomainJson.freeze(arguments)! as Map<String, Object?>;

  final String toolIdentity;
  final EffectControl effectControl;
  final Map<String, Object?> arguments;
}

abstract interface class HostCapabilityPort {
  HostCapabilityKind get kind;

  Future<Object?> execute(HostCapabilityProposal proposal);
}

final class HostCapabilityRegistry {
  HostCapabilityRegistry(Iterable<HostCapabilityPort> capabilities)
      : _capabilities =
            Map<HostCapabilityKind, HostCapabilityPort>.unmodifiable(
          <HostCapabilityKind, HostCapabilityPort>{
            for (final capability in capabilities) capability.kind: capability,
          },
        ) {
    if (_capabilities.length != capabilities.length) {
      throw ArgumentError('Host capability kinds must be unique.');
    }
  }

  final Map<HostCapabilityKind, HostCapabilityPort> _capabilities;

  HostCapabilityPort require(HostCapabilityKind kind) {
    final capability = _capabilities[kind];
    if (capability == null) {
      throw StateError('Host capability ${kind.name} is not registered.');
    }
    return capability;
  }
}
