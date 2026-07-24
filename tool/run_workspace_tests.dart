import 'dart:async';
import 'dart:io';

const _packageDirectories = <String>[
  'provider',
  'ai',
  'provider_utils',
  'openai',
  'openai_compatible',
  'anthropic',
  'protocol_utils',
  'acp',
  'mcp',
  'agent_kernel',
  'agent_io',
  'lsp',
  'dap',
  'dart',
];

Future<void> main() async {
  final root = Directory.current.absolute;
  for (final package in _packageDirectories) {
    final directory = Directory.fromUri(
      root.uri.resolve('packages/$package/'),
    );
    if (!File.fromUri(directory.uri.resolve('pubspec.yaml')).existsSync() ||
        !Directory.fromUri(directory.uri.resolve('test/')).existsSync()) {
      stderr.writeln(
        'Workspace test package is incomplete: packages/$package.',
      );
      exitCode = 1;
      return;
    }

    stdout.writeln('==> packages/$package');
    final process = await Process.start(
      Platform.resolvedExecutable,
      const <String>['test'],
      workingDirectory: directory.path,
      mode: ProcessStartMode.inheritStdio,
    );
    int result;
    try {
      result = await process.exitCode.timeout(const Duration(minutes: 2));
    } on TimeoutException {
      process.kill();
      try {
        await process.exitCode.timeout(const Duration(seconds: 5));
      } on TimeoutException {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      stderr.writeln('Workspace test timed out: packages/$package.');
      exitCode = 1;
      return;
    }
    if (result != 0) {
      stderr.writeln(
        'Workspace test failed: packages/$package (exit $result).',
      );
      exitCode = result;
      return;
    }
  }

  stdout.writeln(
    'All ${_packageDirectories.length} workspace packages passed.',
  );
}
