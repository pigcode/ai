import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';

final class DapScriptedPeerReport {
  const DapScriptedPeerReport({
    required this.scenarios,
    required this.reverseProposalCount,
    required this.lifecycle,
  });

  final List<String> scenarios;
  final int reverseProposalCount;
  final String lifecycle;
}

final class DapScriptedPeer {
  Future<DapScriptedPeerReport> run() async {
    final scenarios = <String>[];
    final connection = DapConnection();
    final initialize = connection.beginInitialize();
    connection.completeInitialize(
      initialize.seq,
      const <String, Object?>{
        'supportsConfigurationDoneRequest': true,
        'supportsCancelRequest': true,
      },
    );
    scenarios.add('initialize');

    final launch = connection.beginLaunch(const <String, Object?>{});
    connection
      ..completeStart(launch.seq)
      ..receiveEvent(
        seq: 1,
        event: 'initialized',
        body: const <String, Object?>{},
      );
    scenarios.add('launch');

    final breakpoints = connection.beginRequest(
      'setBreakpoints',
      arguments: const <String, Object?>{
        'source': <String, Object?>{'path': '/redacted.dart'},
        'breakpoints': <Object?>[],
      },
    );
    connection.completeResponse(
      requestSeq: breakpoints.seq,
      command: 'setBreakpoints',
    );
    scenarios.add('breakpoints');

    final configuration = connection.beginConfigurationDone();
    connection.completeConfiguration(configuration.seq);
    scenarios.add('configuration');

    connection.receiveEvent(
      seq: 2,
      event: 'stopped',
      body: const <String, Object?>{
        'reason': 'breakpoint',
        'threadId': 1,
      },
    );
    final debug = DapDebugState(connectionId: connection.connectionId)
      ..updateThreads(const [
        <String, Object?>{'id': 1, 'name': 'main'},
      ]);
    final pause = debug.stop(threadId: 1, reason: 'breakpoint');
    scenarios.add('stopped');

    debug
      ..setStackFrames(
        threadId: 1,
        pauseGeneration: pause,
        frames: const [
          <String, Object?>{
            'id': 10,
            'name': 'main',
            'line': 1,
            'column': 1,
          },
        ],
      )
      ..setScopes(
        frameId: 10,
        pauseGeneration: pause,
        scopes: const [
          <String, Object?>{
            'name': 'Locals',
            'variablesReference': 20,
            'expensive': false,
          },
        ],
      )
      ..setVariables(
        variablesReference: 20,
        pauseGeneration: pause,
        variables: const [
          <String, Object?>{
            'name': 'value',
            'value': '1',
            'variablesReference': 0,
          },
        ],
      );
    scenarios.add('stack-variables');

    final continueRequest = connection.beginRequest('continue');
    final cancellations = DapCancellationRegistry(
      capabilities: connection.capabilities,
    )..trackRequest(continueRequest.seq);
    cancellations.cancel(requestId: continueRequest.seq);
    connection.completeResponse(
      requestSeq: continueRequest.seq,
      command: 'continue',
    );
    cancellations.completeRequest(continueRequest.seq);
    debug.continueThread(1);
    scenarios.add('continue');

    DapProgressRegistry()
      ..start(
        progressId: 'continue',
        title: 'Continue',
        requestId: continueRequest.seq,
      )
      ..end(progressId: 'continue');
    scenarios.add('progress-cancel');

    var reverseProposalCount = 0;
    final proposals = DapProposalDispatcher()
      ..register('runInTerminal', (proposal) {
        reverseProposalCount += 1;
        return const <String, Object?>{'processId': 1};
      });
    await Future<Object?>.value(
      proposals.dispatch(
        'runInTerminal',
        const <String, Object?>{
          'cwd': '/workspace',
          'args': <Object?>['dart', 'run'],
        },
      ),
    );
    scenarios.add('reverse-request');

    final disconnect = connection.beginDisconnect();
    connection.completeDisconnect(disconnect.seq);
    scenarios.add('disconnect');
    return DapScriptedPeerReport(
      scenarios: List<String>.unmodifiable(scenarios),
      reverseProposalCount: reverseProposalCount,
      lifecycle: connection.lifecycle.name,
    );
  }
}
