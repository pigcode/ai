import 'dart:io';

import '../src/dap_peer_harness.dart';
import '../src/tooling_peer_cache.dart';

void main() {
  final manifest = ToolingPeerManifest.load(Directory.current);
  final jsDebug = manifest.releaseArchive('js-debug-v1.117.0');
  _expect(
    jsDebug.release == 'v1.117.0' &&
        jsDebug.size == 1216795 &&
        jsDebug.sha256 ==
            'ad8d04ede9d4b75cc290fd5438a65047a06f786d04f604b6112485b36f090772' &&
        jsDebug.revision == '496a6f1a4fc8198bcd563f97b84a07aa39917404',
    'Wrong js-debug archive pin.',
  );

  final report = DapPeerReport(
    peer: 'fixture',
    family: 'dart-debug-adapter',
    release: '3.12.2',
    transport: 'stdio-content-length',
    capabilities: const <String, Object?>{
      'supportsConfigurationDoneRequest': true,
    },
    scenarios: const <String>[
      'initialize',
      'launch',
      'breakpoint',
      'stopped',
      'stack',
      'continue',
      'disconnect',
    ],
    elapsedMilliseconds: 1,
  );
  _expect(
    validateDapPeerReport(report).isEmpty,
    'Complete DAP report should pass.',
  );
  _expect(
    validateDapPeerReport(
      DapPeerReport(
        peer: report.peer,
        family: report.family,
        release: report.release,
        transport: report.transport,
        capabilities: const <String, Object?>{},
        scenarios: const <String>[],
        elapsedMilliseconds: 0,
      ),
    ).isNotEmpty,
    'Empty/skipped DAP report must fail.',
  );
  stdout.writeln('PASS DAP peer matrix report gate');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
