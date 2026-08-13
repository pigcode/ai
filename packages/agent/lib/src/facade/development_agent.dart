import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class DevelopmentAgentPreconditionException implements Exception {
  const DevelopmentAgentPreconditionException(this.code);

  final String code;
}

final class DevelopmentAgentResult {
  const DevelopmentAgentResult(this.text);

  final String text;
}

enum DevelopmentAgentCommandKind {
  startRun,
  attachActiveRun,
  steerActiveRun,
  cancelRun,
  suspendRun,
  resumeRunFromCheckpoint,
}

final class DevelopmentAgentCommand {
  const DevelopmentAgentCommand({
    required this.kind,
    required this.sessionId,
    this.runId,
    this.commandId,
    this.input,
  });

  final DevelopmentAgentCommandKind kind;
  final SessionId sessionId;
  final RunId? runId;
  final CommandId? commandId;
  final String? input;
}

abstract interface class DevelopmentAgentRuntime {
  Future<DevelopmentAgentResult> generate(
    AgentSessionProjection session,
    String prompt,
  );

  Stream<String> stream(
    AgentSessionProjection session,
    String prompt,
  );

  Future<void> command(DevelopmentAgentCommand command);
}

final class DevelopmentAgent {
  const DevelopmentAgent(this.runtime);

  final DevelopmentAgentRuntime runtime;

  Future<DevelopmentAgentResult> generate({
    required AgentSessionProjection session,
    required String prompt,
  }) {
    _requireUsableSession(session);
    return runtime.generate(session, prompt);
  }

  Stream<String> stream({
    required AgentSessionProjection session,
    required String prompt,
  }) {
    _requireUsableSession(session);
    return runtime.stream(session, prompt);
  }

  Future<void> startRun({
    required AgentSessionProjection session,
    required CommandId commandId,
    required String prompt,
  }) {
    _requireUsableSession(session);
    final current = _currentRun(session);
    if (current != null && !current.state.isTerminal) {
      throw const DevelopmentAgentPreconditionException(
        'start_run_requires_no_active_run',
      );
    }
    return runtime.command(
      DevelopmentAgentCommand(
        kind: DevelopmentAgentCommandKind.startRun,
        sessionId: session.id,
        commandId: commandId,
        input: prompt,
      ),
    );
  }

  Future<void> attachActiveRun({
    required AgentSessionProjection session,
  }) {
    final run = _requireRunState(
      session,
      const <AgentRunState>{
        AgentRunState.inProgress,
        AgentRunState.reconciling,
      },
      'attach_requires_active_run',
    );
    return runtime.command(
      DevelopmentAgentCommand(
        kind: DevelopmentAgentCommandKind.attachActiveRun,
        sessionId: session.id,
        runId: run.id,
      ),
    );
  }

  Future<void> steerActiveRun({
    required AgentSessionProjection session,
    required CommandId commandId,
    required String input,
  }) {
    final run = _requireRunState(
      session,
      const <AgentRunState>{AgentRunState.inProgress},
      'steer_requires_in_progress',
    );
    return runtime.command(
      DevelopmentAgentCommand(
        kind: DevelopmentAgentCommandKind.steerActiveRun,
        sessionId: session.id,
        runId: run.id,
        commandId: commandId,
        input: input,
      ),
    );
  }

  Future<void> cancelRun({
    required AgentSessionProjection session,
    required CommandId commandId,
  }) {
    final run = _requireRunState(
      session,
      const <AgentRunState>{
        AgentRunState.pending,
        AgentRunState.inProgress,
        AgentRunState.suspending,
        AgentRunState.suspended,
        AgentRunState.resuming,
        AgentRunState.reconciling,
      },
      'cancel_requires_non_terminal_run',
    );
    return runtime.command(
      DevelopmentAgentCommand(
        kind: DevelopmentAgentCommandKind.cancelRun,
        sessionId: session.id,
        runId: run.id,
        commandId: commandId,
      ),
    );
  }

  Future<void> suspendRun({
    required AgentSessionProjection session,
    required CommandId commandId,
  }) =>
      _stateCommand(
        session,
        commandId,
        DevelopmentAgentCommandKind.suspendRun,
        AgentRunState.inProgress,
        'suspend_requires_in_progress',
      );

  Future<void> resumeRunFromCheckpoint({
    required AgentSessionProjection session,
    required CommandId commandId,
  }) =>
      _stateCommand(
        session,
        commandId,
        DevelopmentAgentCommandKind.resumeRunFromCheckpoint,
        AgentRunState.suspended,
        'resume_requires_suspended',
      );

  Future<void> _stateCommand(
    AgentSessionProjection session,
    CommandId commandId,
    DevelopmentAgentCommandKind kind,
    AgentRunState requiredState,
    String error,
  ) {
    final run =
        _requireRunState(session, <AgentRunState>{requiredState}, error);
    return runtime.command(
      DevelopmentAgentCommand(
        kind: kind,
        sessionId: session.id,
        runId: run.id,
        commandId: commandId,
      ),
    );
  }

  AgentRun _requireRunState(
    AgentSessionProjection session,
    Set<AgentRunState> states,
    String error,
  ) {
    _requireUsableSession(session);
    final run = _currentRun(session);
    if (run == null || !states.contains(run.state)) {
      throw DevelopmentAgentPreconditionException(error);
    }
    return run;
  }

  AgentRun? _currentRun(AgentSessionProjection session) {
    final id = session.currentRunId;
    return id == null ? null : session.runs[id];
  }

  void _requireUsableSession(AgentSessionProjection session) {
    if (session.conversationAvailability !=
            ConversationAvailability.available ||
        session.controlAttachment != ControlAttachment.attached) {
      throw const DevelopmentAgentPreconditionException(
        'session_not_control_attached',
      );
    }
  }
}
