import 'dart:async';
import 'dart:io';

import 'src/tooling_peer_cache.dart';

Future<void> main(List<String> arguments) async {
  final separator = arguments.indexOf('--');
  final sdkIndex = arguments.indexOf('--sdk');
  if (separator < 0 ||
      sdkIndex < 0 ||
      sdkIndex + 1 >= separator ||
      separator + 1 >= arguments.length) {
    stderr.writeln(
      'Usage: dart run tool/run_with_pinned_dart.dart '
      '--sdk <release> -- <dart arguments>',
    );
    exitCode = 64;
    return;
  }
  final release = arguments[sdkIndex + 1];
  final cache = ToolingPeerCache(root: Directory.current);
  final sdk = await cache.ensureDartSdk(release);
  final executable = ToolingPeerCache.dartExecutable(sdk);
  final pubCache = Directory.fromUri(
    cache.cacheRoot.uri.resolve('pub-cache/$release/'),
  )..createSync(recursive: true);
  final process = await Process.start(
    executable.path,
    arguments.sublist(separator + 1),
    workingDirectory: Directory.current.absolute.path,
    environment: <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
      'PUB_CACHE': pubCache.path,
    },
    includeParentEnvironment: false,
    mode: ProcessStartMode.inheritStdio,
  );
  try {
    exitCode = await process.exitCode.timeout(const Duration(minutes: 15));
  } on TimeoutException {
    process.kill();
    await process.exitCode;
    stderr.writeln('Pinned Dart command exceeded its 15 minute deadline.');
    exitCode = 124;
  }
}
