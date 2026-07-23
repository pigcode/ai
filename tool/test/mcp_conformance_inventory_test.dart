import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _expectedPackageHash =
    '2d99f94129bcaa84b8613dfd5ac50f1885cd8e01b72965da57e66ea848b4d0ab';

Future<void> main() async {
  final root = Directory.current;
  final sourceInventory = jsonDecode(
    File(
      '${root.path}/tool/upstream/protocols/'
      'mcp-conformance/v0.1.16/scenarios.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final packageFile = File(
    '${root.path}/tool/conformance/mcp/node_modules/'
    '@modelcontextprotocol/conformance/package.json',
  );
  _expect(
    packageFile.existsSync(),
    'Pinned harness is not installed; run '
    '`npm ci --prefix tool/conformance/mcp --ignore-scripts`.',
  );
  final packageBytes = packageFile.readAsBytesSync();
  _expect(
    sha256.convert(packageBytes).toString() == _expectedPackageHash,
    'Installed MCP conformance package.json hash drifted.',
  );
  final package = jsonDecode(utf8.decode(packageBytes)) as Map<String, Object?>;
  _expect(package['version'] == '0.1.16', 'Installed harness version drifted.');

  final lock = jsonDecode(
    File(
      '${root.path}/tool/conformance/mcp/package-lock.json',
    ).readAsStringSync(),
  ) as Map<String, Object?>;
  final lockPackages = lock['packages']! as Map<String, Object?>;
  final installed =
      lockPackages['node_modules/@modelcontextprotocol/conformance']!
          as Map<String, Object?>;
  _expect(installed['version'] == '0.1.16', 'Lockfile harness is not exact.');

  final result = await Process.run(
    '${root.path}/tool/conformance/mcp/node_modules/.bin/conformance',
    const <String>['list', '--spec-version', '2025-11-25'],
    workingDirectory: root.path,
  );
  _expect(result.exitCode == 0, 'Harness scenario listing failed.');
  final listed = _parseScenarioList(result.stdout as String);
  _expect(
    _sameOrdered(
      listed.client,
      (sourceInventory['client']! as List<Object?>).cast<String>(),
    ),
    'Installed client scenario inventory drifted.',
  );
  _expect(
    _sameOrdered(
      listed.server,
      (sourceInventory['server']! as List<Object?>).cast<String>(),
    ),
    'Installed server scenario inventory drifted.',
  );
  final rejected = await Process.run(
    Platform.resolvedExecutable,
    const <String>[
      'run',
      'tool/run_mcp_conformance.dart',
      '--role',
      'client',
      '--scenario',
      'initialize',
      '--expected-failures',
      'baseline.yaml',
    ],
    workingDirectory: root.path,
  );
  _expect(
    rejected.exitCode == 64 &&
        (rejected.stderr as String).contains(
          'Expected-failure baselines are forbidden',
        ),
    'Conformance runner did not reject an expected-failure baseline.',
  );
  stdout.writeln(
    'MCP conformance inventory validated: '
    '${listed.client.length} client, ${listed.server.length} server.',
  );
}

final class _ScenarioList {
  const _ScenarioList(this.client, this.server);

  final List<String> client;
  final List<String> server;
}

_ScenarioList _parseScenarioList(String source) {
  final client = <String>[];
  final server = <String>[];
  List<String>? target;
  for (final line in const LineSplitter().convert(source)) {
    if (line.startsWith('Server scenarios')) {
      target = server;
    } else if (line.startsWith('Client scenarios')) {
      target = client;
    } else {
      final match = RegExp(r'^  - ([^ ]+) ').firstMatch(line);
      if (match != null) target?.add(match.group(1)!);
    }
  }
  return _ScenarioList(client, server);
}

bool _sameOrdered(List<String> left, List<String> right) =>
    left.length == right.length &&
    List<bool>.generate(
      left.length,
      (index) => left[index] == right[index],
    ).every((same) => same);

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
