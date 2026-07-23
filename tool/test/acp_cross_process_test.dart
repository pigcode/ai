import 'dart:io';

import '../src/acp_peer_harness.dart';

const _peerPath = 'tool/fixtures/acp_peer.dart';

// Compatibility fixture (real-process): P2A-ACP-10
Future<void> main() async {
  final report = await runAcpPeer(
    AcpPeerCommand(
      peer: 'dart-fixed',
      executable: Platform.resolvedExecutable,
      arguments: const <String>[_peerPath],
      workingDirectory: Directory.current.absolute.path,
      promptText: 'interop 🐷',
      artifacts: const <String, String>{'source': _peerPath},
    ),
  );
  _expect(report.protocolVersion == 1, 'Dart peer negotiated wrong version.');
  _expect(report.stopReason == 'end_turn', 'Dart peer did not end the turn.');
  _expect(report.updateCount >= 1, 'Dart peer emitted no updates.');
  _expect(
    report.reverseMethods.contains('fs/read_text_file'),
    'Dart peer did not exercise a reverse request.',
  );
  stdout.writeln('PASS ACP Dart real process ${report.toJson()}');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
