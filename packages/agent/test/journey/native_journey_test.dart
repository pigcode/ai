import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_agent/pigcode_ai_agent.dart';
import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../../../agent_kernel/test/support/kernel_fixture.dart';
import '../../../agent_kernel/test/support/running_kernel_fixture.dart';
import '../../../agent_kernel/test/support/virtual_agent_clock.dart';
import '../../../agent_kernel/test/support/work_policy_fixture.dart';
import '../../../../tool/src/agent_sandbox_crash_harness.dart';
import '../support/scripted_language_model.dart';

void main() {
  test('normal completion journals managed outcome and replays identically',
      () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final request = workRequest(journey.running.runId);
    final disposition = journey.effectDriver.effectDisposition(
      request.toolIdentity,
    );
    expect(disposition.effectControl, EffectControl.managed);
    expect(disposition.writeAheadIntentRequired, isTrue);
    expect(disposition.approvalEvidenceAllowed, isTrue);
    final policy = workPolicy(
      effectControl: EffectControl.managed,
      requireApproval: true,
    );
    final proposed = await journey.fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: journey.running.handle,
        runId: journey.running.runId,
        request: request,
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    final approved = await journey.fixture.kernel.resolveApproval(
      ResolveApprovalCommand(
        commandId: resolveApprovalCommandId,
        handle: proposed.sessionHandle!,
        runId: journey.running.runId,
        approvalId: proposed.approvalId!,
        binding: approvalBinding(
          request,
          proposed.workItemId!,
          policy.version,
        ),
        decision: ApprovalDecision.approve,
        currentPrincipal: request.principal,
      ),
    );
    final executing = await journey.fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: approved.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    final execution = await journey.runChild('write');
    expect(await execution.process.exitCode.timeout(_deadline), 0);
    expect(journey.marker.readAsStringSync(), 'sandboxed\n');
    expect(
        (await journey.launcher.cleanup(execution.process)).confirmed, isTrue);
    final outcome = await journey.fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: executing.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.succeeded,
      ),
    );
    final modelResult = await journey.model(
      'Tool succeeded after managed approval.',
    );
    expect(modelResult, 'converged');
    await journey.commitTerminal(
      outcome.sessionHandle!,
      TerminalOutcome.completed,
    );

    final events = await journey.events();
    expect(
      events.where((event) => event.type == AgentEventType.runCompleted),
      hasLength(1),
    );
    expect(
      events.any((event) => event.type == AgentEventType.workSucceeded),
      isTrue,
    );
    final types = events.map((event) => event.type).toList();
    expect(
      types.indexOf(AgentEventType.workProposed),
      lessThan(types.indexOf(AgentEventType.workPolicyEvaluated)),
    );
    expect(
      types.indexOf(AgentEventType.workPolicyEvaluated),
      lessThan(types.indexOf(AgentEventType.workApprovalRequested)),
    );
    expect(
      types.indexOf(AgentEventType.workApprovalResolved),
      lessThan(types.indexOf(AgentEventType.workExecutionStarted)),
    );
    await journey.expectReplayStable();
  });

  test('tool failure is typed, model-visible, journaled, and replay-stable',
      () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final proposed = await journey.proposeWithoutApproval();
    final executing = await journey.fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: proposed.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    final execution = await journey.runChild('fail');
    final stderr =
        await execution.process.stderr.transform(utf8.decoder).join();
    expect(await execution.process.exitCode.timeout(_deadline), 17);
    expect(stderr, contains('typed-tool-failure'));
    expect(
        (await journey.launcher.cleanup(execution.process)).confirmed, isTrue);
    final outcome = await journey.fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: executing.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.failed,
      ),
    );
    expect(await journey.model('typed-tool-failure exit=17'), 'failure-seen');
    await journey.commitTerminal(
        outcome.sessionHandle!, TerminalOutcome.failed);

    expect(
      (await journey.fixture.kernel.loadProjection(journey.running.sessionId))
          .workItems[proposed.workItemId]!
          .state,
      WorkItemState.failed,
    );
    expect(journey.marker.existsSync(), isFalse);
    await journey.expectReplayStable();
  });

  test('approval deny records denied WorkItem and executes no side effect',
      () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final controlRoot = Directory('${journey.root.path}/deny-control')
      ..createSync();
    final controlExecutor = await _AdversarialHostExecutor.start(controlRoot);
    await controlExecutor.execute();
    expect(controlExecutor.calls, 1);
    expect(controlExecutor.marker.existsSync(), isTrue);
    expect(controlExecutor.spawnedPids, hasLength(1));
    expect(controlExecutor.networkConnections, 1);
    await controlExecutor.close();

    final deniedRoot = Directory('${journey.root.path}/denied-effects')
      ..createSync();
    final executor = await _AdversarialHostExecutor.start(deniedRoot);
    addTearDown(executor.close);
    final request = workRequest(journey.running.runId);
    final disposition = journey.effectDriver.effectDisposition(
      request.toolIdentity,
    );
    expect(disposition.effectControl, EffectControl.managed);
    expect(disposition.writeAheadIntentRequired, isTrue);
    final policy = workPolicy(
      effectControl: EffectControl.managed,
      requireApproval: true,
    );
    final proposed = await journey.fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: journey.running.handle,
        runId: journey.running.runId,
        request: request,
        policyVersion: policy.version,
      ),
      policy: policy,
    );
    await journey.fixture.kernel.resolveApproval(
      ResolveApprovalCommand(
        commandId: resolveApprovalCommandId,
        handle: proposed.sessionHandle!,
        runId: journey.running.runId,
        approvalId: proposed.approvalId!,
        binding: approvalBinding(
          request,
          proposed.workItemId!,
          policy.version,
        ),
        decision: ApprovalDecision.deny,
        currentPrincipal: request.principal,
      ),
    );
    await journey.executeHostOnlyAfterApproval(
      proposed.workItemId!,
      executor,
    );

    final projection =
        await journey.fixture.kernel.loadProjection(journey.running.sessionId);
    expect(
      projection.workItems[proposed.workItemId]!.state,
      WorkItemState.denied,
    );
    expect(executor.calls, 0);
    expect(executor.marker.existsSync(), isFalse);
    expect(executor.spawnedPids, isEmpty);
    expect(executor.networkConnections, 0);
    expect(deniedRoot.listSync(), isEmpty);
    await journey.expectReplayStable();
  });

  test('cancel mid-tool cleans process tree before run.cancelled', () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final proposed = await journey.proposeWithoutApproval();
    final executing = await journey.fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: proposed.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    final execution = await journey.runChild('hang');
    expect(
      await execution.process.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .first
          .timeout(_deadline),
      'READY',
    );
    final cancel = await journey.fixture.kernel.cancelRun(
      CancelRunCommand(
        commandId: cancelCommandId,
        handle: executing.sessionHandle!,
        runId: journey.running.runId,
      ),
    );
    final cleanup = await journey.launcher.cleanup(execution.process);
    expect(cleanup.confirmed, isTrue, reason: 'P4-TM-PROC-01');
    final cancelledWork = await journey.fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: cancel.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.cancelled,
      ),
    );
    await journey.commitTerminal(
      cancelledWork.sessionHandle!,
      TerminalOutcome.cancelled,
      hasMatchingCancellationIntent: true,
      executionContainmentProven: true,
    );

    final projection =
        await journey.fixture.kernel.loadProjection(journey.running.sessionId);
    expect(
      projection.runs[journey.running.runId]!.state,
      AgentRunState.cancelled,
    );
    await journey.expectReplayStable();
  });

  test('observedOnly executes sandboxed without managed approval evidence',
      () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final disposition =
        journey.effectDriver.effectDisposition('external.observed');
    expect(disposition.effectControl, EffectControl.observedOnly);
    expect(disposition.writeAheadIntentRequired, isFalse);
    expect(disposition.approvalEvidenceAllowed, isFalse);
    expect(disposition.sandboxRequired, isTrue);
    final execution = await journey.runChild('write');
    expect(await execution.process.exitCode.timeout(_deadline), 0);
    expect(journey.marker.readAsStringSync(), 'sandboxed\n');
    expect(
      (await journey.launcher.cleanup(execution.process)).confirmed,
      isTrue,
    );
    await journey.commitTerminal(
      journey.running.handle,
      TerminalOutcome.completed,
    );
    final events = await journey.events();
    expect(
      events.where(
        (event) =>
            event.type == AgentEventType.workApprovalRequested ||
            event.type == AgentEventType.workApprovalResolved,
      ),
      isEmpty,
    );
    expect(
      events.where((event) => event.type.family == AgentEventFamily.work),
      isEmpty,
    );
    await journey.expectReplayStable();
  });

  test('caller cannot forge observedOnly tool into managed Host execution',
      () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final root = Directory('${journey.root.path}/forged-effects')..createSync();
    final executor = await _AdversarialHostExecutor.start(root);
    addTearDown(executor.close);
    await expectLater(
      journey.executeCallerProposal(
        'external.observed',
        const <String, Object?>{
          'effectControl': 'managed',
          'approvalEvidence': 'forged',
        },
        executor,
      ),
      throwsA(
        isA<NativeAgentDriverException>().having(
          (error) => error.code,
          'code',
          'proposal_metadata_privilege_escalation',
        ),
      ),
    );
    expect(executor.calls, 0);
    expect(executor.spawnedPids, isEmpty);
    expect(executor.networkConnections, 0);
    expect(root.listSync(), isEmpty);
    await journey.expectReplayStable();
  });

  test('SIGKILL Host recovers through Driver Kernel Host path', () async {
    final journey = await _NativeJourney.start();
    addTearDown(journey.dispose);
    final disposition = journey.effectDriver.effectDisposition('tool:test');
    expect(disposition.effectControl, EffectControl.managed);
    expect(disposition.writeAheadIntentRequired, isTrue);
    expect(disposition.replayAllowed, isTrue);

    final proposed = await journey.proposeWithoutApproval();
    final executing = await journey.fixture.kernel.startWorkExecution(
      StartWorkExecutionCommand(
        commandId: startWorkCommandId,
        handle: proposed.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
      ),
    );
    final report = await runAgentSandboxCrashScenario(
      'effect-mid-execution',
      workspaceRoot: journey.workspaceRoot,
    );
    expect(report.boundaryEvidence['phase'],
        'side-effect-started-before-completion');
    expect(report.cleanupConfirmed, isTrue);
    expect(report.residualProcess, isFalse);
    expect(report.outcomeReplayed, isFalse);

    final unknown = await journey.fixture.kernel.recordWorkItemOutcome(
      RecordWorkItemOutcomeCommand(
        commandId: outcomeWorkCommandId,
        handle: executing.sessionHandle!,
        runId: journey.running.runId,
        workItemId: proposed.workItemId!,
        outcome: WorkItemOutcome.outcomeUnknown,
        externalEffectSucceededButResultMissing: true,
      ),
    );
    final reconciling = await journey.fixture.kernel.reconcileRun(
      ReconcileRunCommand(
        commandId: reconcileCommandId,
        handle: unknown.sessionHandle!,
        runId: journey.running.runId,
        reason: 'host-sigkill-effect-outcome-unknown',
      ),
    );
    var projection =
        await journey.fixture.kernel.loadProjection(journey.running.sessionId);
    expect(
      projection.workItems[proposed.workItemId]!.state,
      WorkItemState.outcomeUnknown,
    );
    expect(
      projection.runs[journey.running.runId]!.state,
      AgentRunState.reconciling,
    );
    await journey.commitTerminal(
      reconciling.sessionHandle!,
      TerminalOutcome.interrupted,
    );
    projection =
        await journey.fixture.kernel.loadProjection(journey.running.sessionId);
    expect(
      projection.runs[journey.running.runId]!.state,
      AgentRunState.interrupted,
    );
    await journey.expectReplayStable();
  }, timeout: Timeout(_crashJourneyTestBudget));
}

const _deadline = Duration(seconds: 12);
const _crashJourneyTestBudget = Duration(minutes: 3);

final class _NativeJourney {
  _NativeJourney._({
    required this.fixture,
    required this.running,
    required this.root,
    required this.launcher,
  }) : marker = File('${root.path}/effect.txt');

  static Future<_NativeJourney> start() async {
    final root = Directory.systemTemp.createTempSync('p4-native-journey-');
    final fixture = await _PersistentKernelFixture.start(root);
    final running = await _preparePersistentRunningRun(fixture);
    final backend = Platform.isMacOS
        ? SeatbeltSandboxBackend()
        : LandlockSeccompSandboxBackend();
    backend.probe().requireProductionReady();
    return _NativeJourney._(
      fixture: fixture,
      running: running,
      root: root,
      launcher: SandboxedProcessLauncher.unsafeDev(backend),
    );
  }

  final _PersistentKernelFixture fixture;
  final RunningKernelState running;
  final Directory root;
  final SandboxedProcessLauncher launcher;
  final File marker;
  final List<SandboxedProcess> _live = <SandboxedProcess>[];
  late final NativeAgentDriver<Object?, Object?, Object?> effectDriver =
      NativeAgentDriver<Object?, Object?, Object?>(
    NativeDriverCapabilities.unsafeDev(
      toolEffects: const <String, EffectControl>{
        'tool:test': EffectControl.managed,
        'external.observed': EffectControl.observedOnly,
        'external.unknown': EffectControl.unknown,
      },
    ),
  );

  Directory get workspaceRoot => Directory('packages').existsSync()
      ? Directory.current.absolute
      : Directory('../..').absolute;

  Future<AgentCommandReceipt> proposeWithoutApproval() {
    final disposition = effectDriver.effectDisposition('tool:test');
    if (disposition.effectControl != EffectControl.managed ||
        !disposition.writeAheadIntentRequired ||
        !disposition.sandboxRequired) {
      throw StateError('managed Driver disposition was not enforced');
    }
    return fixture.kernel.proposeWorkItem(
      ProposeWorkItemCommand(
        commandId: proposeWorkCommandId,
        handle: running.handle,
        runId: running.runId,
        request: workRequest(running.runId),
        policyVersion: 'policy/v1',
      ),
      policy: workPolicy(effectControl: EffectControl.managed),
    );
  }

  Future<({SandboxedProcess process})> runChild(String mode) async {
    final fixture = File.fromUri(
      workspaceRoot.uri.resolve('tool/fixtures/native_journey_child.dart'),
    );
    final process = await launcher.launch(
      SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: root.path,
            access: SandboxPathAccess.readWrite,
          ),
          SandboxPathRule(
            path: workspaceRoot.path,
            access: SandboxPathAccess.readOnly,
          ),
          SandboxPathRule(
            path: File(Platform.resolvedExecutable).parent.parent.path,
            access: SandboxPathAccess.readOnly,
          ),
        ],
      ),
      HostCommand(
        executable: Platform.resolvedExecutable,
        arguments: <String>[
          fixture.path,
          mode,
          marker.path,
        ],
        workingDirectory: workspaceRoot.path,
      ),
    );
    _live.add(process);
    return (process: process);
  }

  Future<void> executeHostOnlyAfterApproval(
    WorkItemId workItemId,
    _HostExecutor executor,
  ) async {
    final projection = await fixture.kernel.loadProjection(running.sessionId);
    if (projection.workItems[workItemId]!.state != WorkItemState.approved) {
      return;
    }
    await executor.execute();
  }

  Future<void> executeCallerProposal(
    String toolIdentity,
    Map<String, Object?> proposalMetadata,
    _HostExecutor executor,
  ) async {
    effectDriver.effectDisposition(
      toolIdentity,
      proposalMetadata: proposalMetadata,
    );
    await executor.execute();
  }

  Future<String> model(String prompt) async {
    final scripted = prompt.contains('failure')
        ? const <String>['failure-seen']
        : const <String>['converged'];
    final driver = NativeAgentDriver<String, String, Never>(
      NativeDriverCapabilities.unsafeDev(
        toolEffects: const <String, EffectControl>{
          'tool:test': EffectControl.managed,
        },
      ),
      toolLoopAgent: ToolLoopAgent<String, String, Never>(
        model: ScriptedLanguageModel(scripted),
      ),
    );
    final projection = await fixture.kernel.loadProjection(running.sessionId);
    return (await DevelopmentAgent(driver).generate(
      session: projection,
      prompt: prompt,
    ))
        .text;
  }

  Future<void> commitTerminal(
    AgentSessionHandle handle,
    TerminalOutcome outcome, {
    bool hasMatchingCancellationIntent = false,
    bool executionContainmentProven = false,
  }) async {
    await fixture.kernel.commitTerminal(
      handle: handle,
      proposal: TerminalProposal(
        runId: running.runId,
        attemptId: running.attemptId,
        executionEpoch: 1,
        outcome: outcome,
        sourceId: 'native-journey',
        sourceWatermark: 0,
        causationId: running.driverCommandId,
        payload: const <String, Object?>{},
        hasMatchingCancellationIntent: hasMatchingCancellationIntent,
        executionContainmentProven: executionContainmentProven,
      ),
      drainedSourceWatermarks: const <String, int>{'native-journey': 0},
    );
  }

  Future<List<AgentEvent>> events() async {
    final page = await fixture.store.readEvents(running.sessionId, limit: 256);
    return page.events;
  }

  Future<void> expectReplayStable() async {
    final first = await fixture.kernel.loadProjection(running.sessionId);
    final previousKernel = fixture.kernel;
    await fixture.restartKernel();
    expect(identical(fixture.kernel, previousKernel), isFalse);
    final replayed = await fixture.kernel.loadProjection(running.sessionId);
    expect(jsonEncode(replayed.toJson()), jsonEncode(first.toJson()));
  }

  Future<void> dispose() async {
    for (final process in _live) {
      try {
        await launcher.cleanup(process).timeout(_deadline);
      } on Object {
        process.kill(ProcessSignal.sigkill);
      }
    }
    await fixture.close();
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}

final class _PersistentKernelFixture {
  _PersistentKernelFixture._({
    required this.storeRoot,
    required this.coordinator,
    required this.store,
    required this.kernel,
  });

  static Future<_PersistentKernelFixture> start(Directory journeyRoot) async {
    final storeRoot = Directory('${journeyRoot.path}/store')..createSync();
    final coordinator = await FileStoreCoordinator.start(
      StoreLayout.open(storeRoot),
    );
    final store = await _openStore(storeRoot, coordinator);
    return _PersistentKernelFixture._(
      storeRoot: storeRoot,
      coordinator: coordinator,
      store: store,
      kernel: _newKernel(store),
    );
  }

  final Directory storeRoot;
  final FileStoreCoordinator coordinator;
  FileAgentStore store;
  AgentKernel kernel;

  static Future<FileAgentStore> _openStore(
    Directory root,
    FileStoreCoordinator coordinator,
  ) =>
      FileAgentStore.open(
        root: root,
        coordinator: coordinator.client,
        options: const FileStoreOptions(
          rootAccessPolicy: FileStoreRootAccessPolicy.explicitTestOnly,
        ),
      );

  static AgentKernel _newKernel(FileAgentStore store) => AgentKernel(
        store: store,
        idGenerator: OpaqueIdGenerator(),
        clock: VirtualAgentClock(DateTime.utc(2026, 7, 24)),
        durability: AgentStoreDurability.processCrashFlush,
      );

  Future<void> restartKernel() async {
    store = await _openStore(storeRoot, coordinator);
    kernel = _newKernel(store);
  }

  Future<(AgentCommandReceipt, CreateSessionCommand)> createSession() async {
    final root = await store.loadRoot();
    final command = CreateSessionCommand(
      commandId: createCommandId,
      expectedRootHead: root.head,
      definitionRef: const AgentDefinitionRef('agent:native-journey'),
      capabilitySnapshot: CapabilitySnapshot(const <String, Object?>{
        'run': true,
      }),
    );
    return (await kernel.createSession(command), command);
  }

  Future<void> close() => coordinator.close();
}

Future<RunningKernelState> _preparePersistentRunningRun(
  _PersistentKernelFixture fixture,
) async {
  final (created, _) = await fixture.createSession();
  final started = await fixture.kernel.startRun(
    StartRunCommand(
      commandId: startCommandId,
      handle: created.sessionHandle!,
      input: const <String, Object?>{'prompt': 'native journey'},
    ),
  );
  final runId = started.runId!;
  final attemptEvent = _journeyEvent(
    eventId: runningAttemptEventId,
    sequence: 4,
    type: AgentEventType.runAttemptStarted,
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
  );
  final startedEvent = _journeyEvent(
    eventId: runningStartedEventId,
    sequence: 5,
    type: AgentEventType.runStarted,
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
  );
  final receipt = await fixture.store.append(
    AgentStoreTransaction(
      sessionId: created.sessionId,
      expectedHead: started.sessionHandle!.head,
      newIdAllocations: <AgentStoreIdAllocation>[
        AgentStoreIdAllocation(runningDriverCommandId),
        AgentStoreIdAllocation(runningAttemptId),
        AgentStoreIdAllocation(runningAttemptEventId),
        AgentStoreIdAllocation(runningStartedEventId),
      ],
      events: <AgentEvent>[attemptEvent, startedEvent],
    ),
    requestedDurability: AgentStoreDurability.processCrashFlush,
  );
  return RunningKernelState(
    sessionId: created.sessionId,
    runId: runId,
    attemptId: runningAttemptId,
    handle: AgentSessionHandle(
      sessionId: created.sessionId,
      projectionGeneration: receipt.afterHead.generation,
      head: receipt.afterHead,
    ),
    driverCommandId: runningDriverCommandId,
  );
}

AgentEvent _journeyEvent({
  required EventId eventId,
  required int sequence,
  required AgentEventType type,
  required SessionId sessionId,
  required RunId runId,
  required AttemptId attemptId,
}) =>
    AgentEvent(
      eventId: eventId,
      schemaVersion: 1,
      sessionId: sessionId,
      sequence: sequence,
      recordedAt: DateTime.now().toUtc(),
      type: type,
      runId: runId,
      attemptId: attemptId,
      causationId: runningDriverCommandId,
      payload: type == AgentEventType.runAttemptStarted
          ? const <String, Object?>{'executionEpoch': 1}
          : const <String, Object?>{},
      metadata: AgentEventMetadata.empty(),
    );

abstract interface class _HostExecutor {
  Future<void> execute();
}

final class _AdversarialHostExecutor implements _HostExecutor {
  _AdversarialHostExecutor._(this.root, this.server)
      : marker = File('${root.path}/host-was-called.txt');

  static Future<_AdversarialHostExecutor> start(Directory root) async {
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final executor = _AdversarialHostExecutor._(root, server);
    executor._subscription = server.listen((socket) {
      executor.networkConnections += 1;
      socket.drain<void>().whenComplete(socket.destroy);
    });
    return executor;
  }

  final Directory root;
  final ServerSocket server;
  final File marker;
  final List<Process> _processes = <Process>[];
  late final StreamSubscription<Socket> _subscription;
  int calls = 0;
  int networkConnections = 0;

  List<int> get spawnedPids =>
      _processes.map((process) => process.pid).toList(growable: false);

  @override
  Future<void> execute() async {
    calls += 1;
    await marker.writeAsString('host executor invoked\n', flush: true);
    final workspaceRoot = Directory('packages').existsSync()
        ? Directory.current.absolute
        : Directory('../..').absolute;
    final fixture = File.fromUri(
      workspaceRoot.uri.resolve('tool/fixtures/native_journey_child.dart'),
    );
    final process = await Process.start(
      Platform.resolvedExecutable,
      <String>[fixture.path, 'fail', marker.path],
      workingDirectory: workspaceRoot.path,
      runInShell: false,
    );
    _processes.add(process);
    process.stdout.drain<void>();
    process.stderr.drain<void>();
    await process.exitCode.timeout(_deadline);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      server.port,
      timeout: const Duration(seconds: 2),
    );
    socket.write('adversarial-host-call');
    await socket.flush();
    await socket.close();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (networkConnections == 0 && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
  }

  Future<void> close() async {
    for (final process in _processes) {
      if (ProcessGroup.captureIdentity(process.pid) != null) {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode.timeout(const Duration(seconds: 2));
      }
    }
    await _subscription.cancel();
    await server.close();
  }
}
