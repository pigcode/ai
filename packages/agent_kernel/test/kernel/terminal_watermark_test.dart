import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

import '../support/terminal_test_support.dart';

void main() {
  test('terminal remains staged until its source watermark is drained', () {
    final projection = terminalProjection();
    final before = projection.toJson();
    final proposal = terminalProposal();

    final blocked = const TerminalBarrier().evaluate(
      projection: projection,
      proposal: proposal,
      drainedSourceWatermarks: const <String, int>{'source:test': 9},
    );
    expect(
      blocked.blockers,
      contains(TerminalBarrierBlocker.sourceNotDrained),
    );
    expect(projection.toJson(), before);
    expect(projection.runs[terminalRunId]!.state, AgentRunState.inProgress);

    final ready = const TerminalBarrier().evaluate(
      projection: projection,
      proposal: proposal,
      drainedSourceWatermarks: const <String, int>{'source:test': 10},
    );
    expect(ready.isReady, isTrue);
    expect(projection.toJson(), before);
  });
}
