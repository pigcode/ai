import 'dart:io';

import '../src/lsp_peer_harness.dart';

void main() {
  final report = LspPeerReport(
    peer: 'fixture',
    family: 'dart-language-server',
    release: '3.12.2',
    transport: 'stdio-content-length',
    capabilities: const <String, Object?>{'hoverProvider': true},
    scenarios: const <String>[
      'initialize',
      'open',
      'hover',
      'completion',
      'shutdown',
    ],
    elapsedMilliseconds: 1,
  );
  _expect(
    validateLspPeerReport(report).isEmpty,
    'Complete LSP report should pass.',
  );
  _expect(
    validateLspPeerReport(
      LspPeerReport(
        peer: report.peer,
        family: report.family,
        release: report.release,
        transport: report.transport,
        capabilities: const <String, Object?>{},
        scenarios: const <String>[],
        elapsedMilliseconds: 0,
      ),
    ).isNotEmpty,
    'Empty/skipped LSP report must fail.',
  );
  stdout.writeln('PASS LSP peer matrix report gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
