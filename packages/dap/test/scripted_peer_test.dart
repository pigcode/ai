import 'package:test/test.dart';

import 'support/scripted_peer.dart';

void main() {
  test('runs the deterministic DAP client/adapter profile', () async {
    final report = await DapScriptedPeer().run();
    expect(
        report.scenarios,
        containsAll(const [
          'initialize',
          'launch',
          'breakpoints',
          'configuration',
          'stopped',
          'stack-variables',
          'continue',
          'progress-cancel',
          'reverse-request',
          'disconnect',
        ]));
    expect(report.reverseProposalCount, 1);
    expect(report.lifecycle, 'disconnected');
  });
}
