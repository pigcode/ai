import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  final workspaceRoot = Directory('packages').existsSync()
      ? Directory.current.absolute
      : Directory('../..').absolute;
  final dartPeerSkip = Platform.version.startsWith('3.12.2') && Platform.isMacOS
      ? 'SKIP-MANIFEST Dart 3.12.2 peer accepted launch but exact-port '
          'Seatbelt VM-service handshake did not converge'
      : 'SKIP-MANIFEST dart-debug-adapter pin 3.12.2 unavailable';
  final jsDebugEntrypoint = File.fromUri(
    workspaceRoot.uri.resolve(
      '.dart_tool/tooling-peer-cache/releases/js-debug-v1.117.0/'
      'js-debug/src/dapDebugServer.js',
    ),
  );

  test(
    'Dart Debug Adapter sandbox launch breakpoint continue terminate',
    () async {
      final fixture = Directory.fromUri(
        workspaceRoot.uri.resolve('tool/fixtures/dap/dart_app/'),
      );
      final temporary = Directory.systemTemp.createTempSync('p4-dap-sandbox-');
      final workspace = Directory('${temporary.path}/workspace');
      final reserved = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      final vmServicePort = reserved.port;
      await reserved.close();
      Directory('${workspace.path}/bin').createSync(recursive: true);
      File('${fixture.path}/bin/main.dart')
          .copySync('${workspace.path}/bin/main.dart');
      File('${fixture.path}/pubspec.yaml')
          .copySync('${workspace.path}/pubspec.yaml');
      Directory('${workspace.path}/.dart_tool').createSync();
      File('${workspace.path}/.dart_tool/package_config.json')
          .writeAsStringSync(
        jsonEncode(<String, Object?>{
          'configVersion': 2,
          'packages': <Object?>[
            <String, Object?>{
              'name': 'pigcode_dap_dart_fixture',
              'rootUri': '../',
              'packageUri': 'lib/',
              'languageVersion': '3.6',
            },
          ],
        }),
      );
      final backend = SeatbeltSandboxBackend();
      final launcher = SandboxedProcessLauncher.unsafeDev(backend);
      final policy = SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: File(Platform.resolvedExecutable).parent.parent.path,
            access: SandboxPathAccess.readOnly,
          ),
          SandboxPathRule(
            path: temporary.path,
            access: SandboxPathAccess.readWrite,
          ),
        ],
        networkAllowlist: <SandboxNetworkEndpoint>[
          SandboxNetworkEndpoint(host: 'localhost', port: vmServicePort),
        ],
      );
      final environment = <String, String>{
        if (Platform.environment['PATH'] case final String path) 'PATH': path,
        'PUB_CACHE': '${temporary.path}/pub-cache',
        'HOME': temporary.path,
        'TMPDIR': temporary.path,
      };
      SandboxedProcess? adapter;
      try {
        final sdkBin = File(Platform.resolvedExecutable).parent;
        final dartExecutable = '${sdkBin.path}/dart';
        final debuggeeProbe = await launcher.launch(
          policy,
          HostCommand(
            executable: dartExecutable,
            arguments: <String>['${workspace.path}/bin/main.dart'],
            workingDirectory: workspace.path,
            environment: environment,
          ),
        );
        final debuggeeError =
            await debuggeeProbe.stderr.transform(utf8.decoder).join();
        expect(
          await debuggeeProbe.exitCode.timeout(const Duration(seconds: 10)),
          0,
          reason: debuggeeError,
        );
        await launcher.cleanup(debuggeeProbe);
        adapter = await launcher.launch(
          policy,
          HostCommand(
            executable: '${sdkBin.path}/dartaotruntime',
            arguments: <String>[
              '--resolved_executable_name=$dartExecutable',
              '${sdkBin.path}/snapshots/dartdev_aot.dart.snapshot',
              'debug_adapter',
            ],
            workingDirectory: workspace.path,
            environment: environment,
          ),
        );
        final client = _DapClient(adapter);
        final program = File('${workspace.path}/bin/main.dart').absolute.path;
        final initialize = await client.request(
          1,
          'initialize',
          const <String, Object?>{
            'adapterID': 'pigcode',
            'linesStartAt1': true,
            'columnsStartAt1': true,
            'pathFormat': 'path',
            'supportsRunInTerminalRequest': false,
          },
        );
        expect(initialize['success'], isTrue);
        await client.sendRequest(
          2,
          'launch',
          <String, Object?>{
            'program': program,
            'cwd': workspace.path,
            'noDebug': false,
            'vmServicePort': vmServicePort,
            'vmAdditionalArgs': <Object?>['--no-dds'],
          },
        );
        await client.event('initialized');
        final breakpointResponse = await client.request(
          3,
          'setBreakpoints',
          <String, Object?>{
            'source': <String, Object?>{'path': program},
            'breakpoints': <Object?>[
              <String, Object?>{'line': 2},
            ],
            'sourceModified': false,
          },
        );
        final breakpointBody =
            breakpointResponse['body'] as Map<String, Object?>? ?? const {};
        expect(
          breakpointBody['breakpoints'],
          isNotEmpty,
          reason: jsonEncode(breakpointResponse),
        );
        await client.request(
          4,
          'configurationDone',
          const <String, Object?>{},
        );
        await client.response(2, 'launch');
        final stopped = await client.event('stopped');
        final threadId =
            ((stopped['body'] as Map<String, Object?>?)?['threadId'] as int?) ??
                1;
        await client.request(
          5,
          'continue',
          <String, Object?>{'threadId': threadId},
        );
        await client.event('terminated');
        await client.request(6, 'disconnect', const <String, Object?>{});
        expect(
          await adapter.exitCode.timeout(const Duration(seconds: 10)),
          0,
        );
        expect(client.stderr, isNot(contains('Operation not permitted')));
      } finally {
        if (adapter != null) await launcher.cleanup(adapter);
        temporary.deleteSync(recursive: true);
      }
    },
    skip: dartPeerSkip,
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'js-debug standalone sandbox launch breakpoint continue terminate',
    () {},
    skip: jsDebugEntrypoint.existsSync()
        ? 'SKIP-MANIFEST js-debug 1.117.0 requires bind(0) and node-cdp '
            'Unix sockets; strict bounded Seatbelt allowlist rejects both'
        : 'SKIP-MANIFEST js-debug-v1.117.0 peer cache unavailable',
  );
}

final class _DapClient {
  _DapClient(SandboxedProcess process)
      : _messages = StreamIterator<Map<String, Object?>>(
          _decodeFrames(process.stdout),
        ) {
    process.stderr.transform(utf8.decoder).listen((chunk) {
      if (_stderr.length < 64 * 1024) _stderr.write(chunk);
    });
    _sink = process.stdin;
  }

  late final IOSink _sink;
  final StreamIterator<Map<String, Object?>> _messages;
  final List<Map<String, Object?>> _pending = <Map<String, Object?>>[];
  final StringBuffer _stderr = StringBuffer();

  String get stderr => _stderr.toString();

  Future<void> sendRequest(
    int sequence,
    String command,
    Map<String, Object?> arguments,
  ) async {
    final body = utf8.encode(
      jsonEncode(<String, Object?>{
        'seq': sequence,
        'type': 'request',
        'command': command,
        'arguments': arguments,
      }),
    );
    _sink.add(ascii.encode('Content-Length: ${body.length}\r\n\r\n'));
    _sink.add(body);
    await _sink.flush();
  }

  Future<Map<String, Object?>> request(
    int sequence,
    String command,
    Map<String, Object?> arguments,
  ) async {
    await sendRequest(sequence, command, arguments);
    return response(sequence, command);
  }

  Future<Map<String, Object?>> response(int sequence, String command) => _next(
        (message) =>
            message['type'] == 'response' &&
            message['request_seq'] == sequence &&
            message['command'] == command,
      );

  Future<Map<String, Object?>> event(String name) => _next(
      (message) => message['type'] == 'event' && message['event'] == name);

  Future<Map<String, Object?>> _next(
    bool Function(Map<String, Object?> message) predicate,
  ) async {
    final pendingIndex = _pending.indexWhere(predicate);
    if (pendingIndex >= 0) return _pending.removeAt(pendingIndex);
    while (await _messages.moveNext().timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw StateError(
            'DAP timeout pending=${jsonEncode(_pending)} stderr=$stderr',
          ),
        )) {
      final message = _messages.current;
      if (message['type'] == 'request') {
        throw StateError(
            'Unexpected DAP reverse request: ${message['command']}');
      }
      if (message['type'] == 'response' && message['success'] != true) {
        throw StateError('DAP request failed: ${message['message']}');
      }
      if (predicate(message)) return message;
      _pending.add(message);
    }
    throw StateError('DAP stream ended: $stderr');
  }
}

Stream<Map<String, Object?>> _decodeFrames(Stream<List<int>> input) async* {
  final bytes = <int>[];
  await for (final chunk in input) {
    bytes.addAll(chunk);
    while (true) {
      final headerEnd = _indexOf(bytes, const <int>[13, 10, 13, 10]);
      if (headerEnd < 0) break;
      final header = ascii.decode(bytes.sublist(0, headerEnd));
      final match = RegExp(r'Content-Length:\s*([0-9]+)', caseSensitive: false)
          .firstMatch(header);
      if (match == null) throw const FormatException('Missing Content-Length.');
      final length = int.parse(match.group(1)!);
      final bodyStart = headerEnd + 4;
      if (bytes.length < bodyStart + length) break;
      final body = bytes.sublist(bodyStart, bodyStart + length);
      bytes.removeRange(0, bodyStart + length);
      yield jsonDecode(utf8.decode(body)) as Map<String, Object?>;
    }
  }
}

int _indexOf(List<int> bytes, List<int> pattern) {
  for (var index = 0; index <= bytes.length - pattern.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset += 1) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}
