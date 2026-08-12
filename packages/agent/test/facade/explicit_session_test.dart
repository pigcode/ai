import 'dart:io';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/scripted_language_model.dart';

void main() {
  test('NativeAgentDriver invokes a scripted ToolLoopAgent', () async {
    final model = ScriptedLanguageModel(<String>['scripted-result']);
    final driver = NativeAgentDriver<String, String, Never>(
      NativeDriverCapabilities.unsafeDev(
        toolEffects: const <String, EffectControl>{},
      ),
      toolLoopAgent: ToolLoopAgent<String, String, Never>(model: model),
    );
    final result = await DevelopmentAgent(
      driver,
    ).generate(session: _session(), prompt: 'hello');

    expect(result.text, 'scripted-result');
  });

  test('generate and stream require an explicit AgentSession', () async {
    final runtime = _Runtime();
    final agent = DevelopmentAgent(runtime);
    final session = _session();

    expect(
        (await agent.generate(session: session, prompt: 'hello')).text, 'ok');
    expect(
      await agent.stream(session: session, prompt: 'hello').single,
      'chunk',
    );
    expect(runtime.sessions, <SessionId>[session.id, session.id]);
  });

  test('architecture 10.2 command by run-state matrix is exhaustive', () async {
    final cases = <_CommandCase>[
      _CommandCase(
        kind: DevelopmentAgentCommandKind.startRun,
        allowed: <AgentRunState?>{
          null,
          AgentRunState.completed,
          AgentRunState.failed,
          AgentRunState.cancelled,
          AgentRunState.interrupted,
        },
        errorCode: 'start_run_requires_no_active_run',
        invoke: (agent, session) => agent.startRun(
          session: session,
          commandId: _commandId(3),
          prompt: 'start',
        ),
      ),
      _CommandCase(
        kind: DevelopmentAgentCommandKind.attachActiveRun,
        allowed: const <AgentRunState?>{
          AgentRunState.inProgress,
          AgentRunState.reconciling,
        },
        errorCode: 'attach_requires_active_run',
        invoke: (agent, session) => agent.attachActiveRun(session: session),
      ),
      _CommandCase(
        kind: DevelopmentAgentCommandKind.steerActiveRun,
        allowed: const <AgentRunState?>{AgentRunState.inProgress},
        errorCode: 'steer_requires_in_progress',
        invoke: (agent, session) => agent.steerActiveRun(
          session: session,
          commandId: _commandId(4),
          input: 'more',
        ),
      ),
      _CommandCase(
        kind: DevelopmentAgentCommandKind.cancelRun,
        allowed: const <AgentRunState?>{
          AgentRunState.pending,
          AgentRunState.inProgress,
          AgentRunState.suspending,
          AgentRunState.suspended,
          AgentRunState.resuming,
          AgentRunState.reconciling,
        },
        errorCode: 'cancel_requires_non_terminal_run',
        invoke: (agent, session) => agent.cancelRun(
          session: session,
          commandId: _commandId(5),
        ),
      ),
      _CommandCase(
        kind: DevelopmentAgentCommandKind.suspendRun,
        allowed: const <AgentRunState?>{AgentRunState.inProgress},
        errorCode: 'suspend_requires_in_progress',
        invoke: (agent, session) => agent.suspendRun(
          session: session,
          commandId: _commandId(6),
        ),
      ),
      _CommandCase(
        kind: DevelopmentAgentCommandKind.resumeRunFromCheckpoint,
        allowed: const <AgentRunState?>{AgentRunState.suspended},
        errorCode: 'resume_requires_suspended',
        invoke: (agent, session) => agent.resumeRunFromCheckpoint(
          session: session,
          commandId: _commandId(7),
        ),
      ),
    ];

    for (final commandCase in cases) {
      for (final state in <AgentRunState?>[null, ...AgentRunState.values]) {
        final runtime = _Runtime();
        final agent = DevelopmentAgent(runtime);
        final session = _session(runState: state);
        if (commandCase.allowed.contains(state)) {
          await commandCase.invoke(agent, session);
          expect(runtime.commands, hasLength(1));
          expect(runtime.commands.single.kind, commandCase.kind);
        } else {
          await expectLater(
            () => commandCase.invoke(agent, session),
            throwsA(
              isA<DevelopmentAgentPreconditionException>().having(
                (error) => error.code,
                'code',
                commandCase.errorCode,
              ),
            ),
          );
          expect(
            runtime.commands,
            isEmpty,
            reason:
                '${commandCase.kind.name} state=${state?.name} leaked command',
          );
        }
      }
    }
  });

  test('every command rejects detached Session before runtime side effects',
      () async {
    final runtime = _Runtime();
    final agent = DevelopmentAgent(runtime);
    final detached = _session(
      runState: AgentRunState.inProgress,
      controlAttachment: ControlAttachment.detached,
    );
    final operations = <Future<void> Function()>[
      () => agent.startRun(
            session: detached,
            commandId: _commandId(8),
            prompt: 'start',
          ),
      () => agent.attachActiveRun(session: detached),
      () => agent.steerActiveRun(
            session: detached,
            commandId: _commandId(9),
            input: 'steer',
          ),
      () => agent.cancelRun(session: detached, commandId: _commandId(10)),
      () => agent.suspendRun(session: detached, commandId: _commandId(11)),
      () => agent.resumeRunFromCheckpoint(
            session: detached,
            commandId: _commandId(12),
          ),
    ];
    for (final operation in operations) {
      await expectLater(
        operation,
        throwsA(
          isA<DevelopmentAgentPreconditionException>().having(
            (error) => error.code,
            'code',
            'session_not_control_attached',
          ),
        ),
      );
    }
    expect(runtime.commands, isEmpty);
  });

  test('generate without explicit Session is a compile-time error', () async {
    final root = Directory('.dart_tool/phase4-negative-compile')
      ..createSync(recursive: true);
    final source = File('${root.path}/missing_session.dart');
    try {
      source.writeAsStringSync('''
import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
void invoke(DevelopmentAgent agent) {
  agent.generate(prompt: 'missing');
}
''');
      final result = await Process.run(
        Platform.resolvedExecutable,
        <String>['analyze', source.path],
      ).timeout(const Duration(seconds: 15));
      expect(result.exitCode, isNot(0));
      expect('${result.stdout}${result.stderr}', contains('session'));
      expect(
        '${result.stdout}${result.stderr}',
        contains('missing_required_argument'),
      );
    } finally {
      if (root.existsSync()) root.deleteSync(recursive: true);
    }
  });
}

final class _Runtime implements DevelopmentAgentRuntime {
  final sessions = <SessionId>[];
  final commands = <DevelopmentAgentCommand>[];

  @override
  Future<DevelopmentAgentResult> generate(
    AgentSessionProjection session,
    String prompt,
  ) async {
    sessions.add(session.id);
    return const DevelopmentAgentResult('ok');
  }

  @override
  Stream<String> stream(
    AgentSessionProjection session,
    String prompt,
  ) async* {
    sessions.add(session.id);
    yield 'chunk';
  }

  @override
  Future<void> command(DevelopmentAgentCommand command) async {
    commands.add(command);
  }
}

CommandId _commandId(int seed) =>
    CommandId.parse('cmd_${'$seed'.padLeft(32, '0')}');

AgentSessionProjection _session({
  AgentRunState? runState,
  ControlAttachment controlAttachment = ControlAttachment.attached,
}) {
  final sessionId = SessionId.parse('ses_${''.padLeft(32, '0')}');
  final runId = RunId.parse('run_${''.padLeft(32, '1')}');
  return AgentSessionProjection(
    id: sessionId,
    journalSequence: 1,
    definitionRef: null,
    capabilitySnapshot: CapabilitySnapshot.empty(),
    conversationAvailability: ConversationAvailability.available,
    controlAttachment: controlAttachment,
    runtimeLiveness: RuntimeLiveness.unknown,
    resumeStateAvailability: ResumeStateAvailability.none,
    currentRunId: runState == null ? null : runId,
    runs: runState == null
        ? const <RunId, AgentRun>{}
        : <RunId, AgentRun>{
            runId: AgentRun(id: runId, state: runState),
          },
    runHistory: runState == null ? const <RunId>[] : <RunId>[runId],
    workItems: const <WorkItemId, WorkItem>{},
    approvals: const <ApprovalId, Approval>{},
    deferredOperations: const <DeferredOperationId, DeferredOperation>{},
    resources: const <RuntimeResourceId, RuntimeResource>{},
  );
}

final class _CommandCase {
  const _CommandCase({
    required this.kind,
    required this.allowed,
    required this.errorCode,
    required this.invoke,
  });

  final DevelopmentAgentCommandKind kind;
  final Set<AgentRunState?> allowed;
  final String errorCode;
  final Future<void> Function(
    DevelopmentAgent agent,
    AgentSessionProjection session,
  ) invoke;
}
