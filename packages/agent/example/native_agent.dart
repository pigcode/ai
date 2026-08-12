import 'dart:async';
import 'dart:io';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

Future<void> main() async {
  final session = AgentSessionProjection(
    id: SessionId.parse('ses_${''.padLeft(32, '1')}'),
    journalSequence: 1,
    definitionRef: null,
    capabilitySnapshot: CapabilitySnapshot.empty(),
    conversationAvailability: ConversationAvailability.available,
    controlAttachment: ControlAttachment.attached,
    runtimeLiveness: RuntimeLiveness.unknown,
    resumeStateAvailability: ResumeStateAvailability.none,
    currentRunId: null,
    runs: const <RunId, AgentRun>{},
    runHistory: const <RunId>[],
    workItems: const <WorkItemId, WorkItem>{},
    approvals: const <ApprovalId, Approval>{},
    deferredOperations: const <DeferredOperationId, DeferredOperation>{},
    resources: const <RuntimeResourceId, RuntimeResource>{},
  );
  final capabilities = NativeDriverCapabilities.unsafeDev(
    toolEffects: const <String, EffectControl>{
      'host.file.write': EffectControl.managed,
    },
  );
  final driver = NativeAgentDriver<String, String, Never>(
    capabilities,
    toolLoopAgent: ToolLoopAgent<String, String, Never>(
      model: _ScriptedModel(),
    ),
  );
  final result = await DevelopmentAgent(driver).generate(
    session: session,
    prompt: 'Inspect the explicit session.',
  );

  Directory root;
  try {
    root = await Directory.systemTemp.createTemp('pigcode-agent-example-');
  } on FileSystemException {
    throw const _ExampleHostException('temporary-root-unavailable');
  }
  try {
    final binding = DriverBinding(
      driverId: 'native-example',
      sessionId: session.id,
      runId: RunId.parse('run_${''.padLeft(32, '2')}'),
      attemptId: AttemptId.parse('att_${''.padLeft(32, '3')}'),
      executionEpoch: 1,
      connectionEpoch: 1,
      manifestCapabilities: capabilities.snapshot,
      sessionCapabilities: capabilities.snapshot,
    );
    final mapping = AiSdkDriverMapping(
      binding,
      capabilities: capabilities,
    );
    final event = mapping.toolCall(
      workItemId: WorkItemId.parse('wrk_${''.padLeft(32, '4')}'),
      toolIdentity: 'host.file.write',
    );
    final proposal = HostCapabilityProposal(
      toolIdentity: 'host.file.write',
      effectControl: EffectControl.values.byName(
        event.payload['effectControl']! as String,
      ),
      arguments: const <String, Object?>{
        'path': 'result.txt',
        'contents': 'scripted-result',
      },
    );
    final registry = HostCapabilityRegistry(<HostCapabilityPort>[
      _TemporaryFileCapability(root),
    ]);
    await registry.require(HostCapabilityKind.file).execute(proposal);
    print(
      'session=${session.id.value} model=${result.text} '
      'effect=${proposal.effectControl.name} host=temp-root',
    );
  } finally {
    await root.delete(recursive: true);
  }
}

final class _ScriptedModel implements LanguageModel {
  @override
  String get modelId => 'phase4-example-scripted';

  @override
  String get provider => 'scripted';

  @override
  String get specificationVersion => 'v4';

  @override
  FutureOr<Map<String, List<RegExp>>> get supportedUrls => const {};

  @override
  Future<LanguageModelGenerateResult> doGenerate(
    LanguageModelCallOptions options,
  ) async =>
      LanguageModelGenerateResult(
        content: const <LanguageModelContent>[TextContent('scripted-result')],
        finishReason: const LanguageModelFinishReason(FinishReasonType.stop),
        usage: const LanguageModelUsage(
          inputTokens: InputTokens(total: 1),
          outputTokens: OutputTokens(total: 1),
        ),
        warnings: const <Warning>[],
      );

  @override
  Future<LanguageModelStreamResult> doStream(
    LanguageModelCallOptions options,
  ) =>
      throw UnsupportedError('The example uses generate().');
}

final class _TemporaryFileCapability implements HostCapabilityPort {
  const _TemporaryFileCapability(this.root);

  final Directory root;

  @override
  HostCapabilityKind get kind => HostCapabilityKind.file;

  @override
  Future<Object?> execute(HostCapabilityProposal proposal) async {
    if (proposal.effectControl != EffectControl.managed) {
      throw const _ExampleHostException('managed-effect-required');
    }
    final path = proposal.arguments['path']! as String;
    if (path.contains('/') || path.contains(r'\') || path == '..') {
      throw const _ExampleHostException('temporary-root-path-denied');
    }
    await File('${root.path}/$path').writeAsString(
      proposal.arguments['contents']! as String,
      flush: true,
    );
    return null;
  }
}

final class _ExampleHostException implements Exception {
  const _ExampleHostException(this.code);

  final String code;
}
