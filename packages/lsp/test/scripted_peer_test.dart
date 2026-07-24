import 'package:test/test.dart';

import 'support/scripted_peer.dart';

void main() {
  test('runs the deterministic LSP client/server profile', () async {
    final report = await LspScriptedPeer().run();

    expect(
        report.scenarios,
        containsAll(const [
          'initialize',
          'document-sync',
          'diagnostics',
          'completion',
          'progress',
          'cancel',
          'dynamic-registration',
          'reverse-request',
          'shutdown',
        ]));
    expect(report.finalDocumentText, 'void main() {}');
    expect(report.reverseProposalCount, 1);
    expect(report.lifecycle, 'exited');
  });
}
