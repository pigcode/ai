import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import '../facade/development_agent.dart';
import 'native_driver_capabilities.dart';

final class NativeAgentDriverException implements Exception {
  const NativeAgentDriverException(this.code);

  final String code;

  @override
  String toString() => 'NativeAgentDriverException($code)';
}

final class NativeEffectDisposition {
  const NativeEffectDisposition({
    required this.effectControl,
    required this.writeAheadIntentRequired,
    required this.approvalEvidenceAllowed,
    required this.replayAllowed,
    required this.sandboxRequired,
    required this.productionTrusted,
    required this.manifestIdentity,
    required this.manifestVersion,
    required this.sandboxCapabilityDigest,
  });

  final EffectControl effectControl;
  final bool writeAheadIntentRequired;
  final bool approvalEvidenceAllowed;
  final bool replayAllowed;
  final bool sandboxRequired;
  final bool productionTrusted;
  final String manifestIdentity;
  final int manifestVersion;
  final String? sandboxCapabilityDigest;
}

final class NativeAgentDriver<Complete, Partial, Element>
    implements DevelopmentAgentRuntime {
  const NativeAgentDriver(
    this.capabilities, {
    this.toolLoopAgent,
    this.commandHandler,
  });

  final NativeDriverCapabilities capabilities;
  final ToolLoopAgent<Complete, Partial, Element>? toolLoopAgent;
  final Future<void> Function(DevelopmentAgentCommand command)? commandHandler;

  @override
  Future<DevelopmentAgentResult> generate(
    AgentSessionProjection session,
    String prompt,
  ) async {
    final agent = toolLoopAgent;
    if (agent == null) {
      throw const NativeAgentDriverException('tool_loop_agent_unbound');
    }
    final result = await agent.generate(prompt: prompt);
    return DevelopmentAgentResult(result.text);
  }

  @override
  Stream<String> stream(
    AgentSessionProjection session,
    String prompt,
  ) {
    final agent = toolLoopAgent;
    if (agent == null) {
      throw const NativeAgentDriverException('tool_loop_agent_unbound');
    }
    return agent.stream(prompt: prompt).textStream;
  }

  @override
  Future<void> command(DevelopmentAgentCommand command) {
    final handler = commandHandler;
    if (handler == null) {
      throw const NativeAgentDriverException('kernel_command_handler_unbound');
    }
    return handler(command);
  }

  NativeEffectDisposition effectDisposition(
    String toolIdentity, {
    Map<String, Object?> proposalMetadata = const <String, Object?>{},
  }) {
    if (proposalMetadata.keys.any(
      const <String>{'effectControl', 'approvalEvidence'}.contains,
    )) {
      throw const NativeAgentDriverException(
        'proposal_metadata_privilege_escalation',
      );
    }
    final control = capabilities.effectFor(toolIdentity);
    return NativeEffectDisposition(
      effectControl: control,
      writeAheadIntentRequired: control == EffectControl.managed ||
          control == EffectControl.interceptable,
      approvalEvidenceAllowed: control == EffectControl.managed ||
          control == EffectControl.interceptable,
      replayAllowed: control != EffectControl.unknown,
      sandboxRequired: true,
      productionTrusted: capabilities.productionTrusted,
      manifestIdentity: capabilities.manifestIdentity,
      manifestVersion: capabilities.manifestVersion,
      sandboxCapabilityDigest: capabilities.sandboxCapabilityDigest,
    );
  }

  void verifySandboxCapabilityDigest(String actualDigest) =>
      capabilities.verifySandboxCapabilityDigest(actualDigest);
}
