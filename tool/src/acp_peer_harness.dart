import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

final class AcpPeerCommand {
  const AcpPeerCommand({
    required this.peer,
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.promptText,
    required this.artifacts,
    this.environment = const <String, String>{},
  });

  final String peer;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
  final String promptText;
  final Map<String, String> artifacts;
  final Map<String, String> environment;
}

final class AcpPeerReport {
  const AcpPeerReport({
    required this.peer,
    required this.protocolVersion,
    required this.stopReason,
    required this.updateCount,
    required this.reverseMethods,
    required this.artifactSha256s,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final int protocolVersion;
  final String stopReason;
  final int updateCount;
  final List<String> reverseMethods;
  final Map<String, String> artifactSha256s;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'protocolVersion': protocolVersion,
        'stopReason': stopReason,
        'updateCount': updateCount,
        'reverseMethods': reverseMethods,
        'artifactSha256s': artifactSha256s,
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

Future<AcpPeerReport> runAcpPeer(
  AcpPeerCommand command, {
  Duration deadline = const Duration(seconds: 30),
}) async {
  final stopwatch = Stopwatch()..start();
  final process = await Process.start(
    command.executable,
    command.arguments,
    workingDirectory: command.workingDirectory,
    environment: <String, String>{
      ..._sanitizedEnvironment(),
      ...command.environment,
    },
    includeParentEnvironment: false,
  );
  final stderrOutput = process.stderr.transform(utf8.decoder).join();
  final transport = _ProcessByteTransport(process);
  final reverseMethods = <String>[];
  final client = AcpClient.fromByteTransport(
    byteTransport: transport,
    capabilities: AcpClientCapabilities(
      readTextFile: true,
      writeTextFile: true,
      terminal: true,
      booleanConfigOptions: true,
    ),
    handlers: AcpHandlerSet(
      requests: <String, AcpRequestHandler>{
        'session/request_permission': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          final params = invocation.params! as JsonObject;
          final options = params['options']! as List<Object?>;
          final first = options.firstOrNull as JsonObject?;
          return <String, Object?>{
            'outcome': first == null
                ? <String, Object?>{'outcome': 'cancelled'}
                : <String, Object?>{
                    'outcome': 'selected',
                    'optionId': first['optionId'],
                  },
          };
        },
        'fs/read_text_file': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{'content': 'fixed peer read'};
        },
        'fs/write_text_file': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{};
        },
        'terminal/create': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{'terminalId': 'fixed-terminal'};
        },
        'terminal/output': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{
            'output': 'fixed output',
            'truncated': false,
            'exitStatus': <String, Object?>{'exitCode': 0},
          };
        },
        'terminal/release': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{};
        },
        'terminal/wait_for_exit': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{
            'exitCode': 0,
          };
        },
        'terminal/kill': (invocation) {
          reverseMethods.add(invocation.descriptor.method);
          return <String, Object?>{};
        },
      },
    ),
  );

  try {
    final negotiated = await client.initialize(
      clientInfo: const <String, Object?>{
        'name': 'pigcode-acp-peer-matrix',
        'version': '1.0.0',
      },
    ).timeout(deadline);
    final created = await client
        .createSession(
          AcpNewSessionRequest.fromJson(
            <String, Object?>{
              'cwd': Directory.current.absolute.path,
              'mcpServers': <Object?>[],
            },
          ),
        )
        .timeout(deadline);
    final sessionId = (created.toJson()! as JsonObject)['sessionId']! as String;
    final prompt = await client
        .prompt(
          AcpPromptRequest.fromJson(
            <String, Object?>{
              'sessionId': sessionId,
              'prompt': <Object?>[
                <String, Object?>{
                  'type': 'text',
                  'text': command.promptText,
                },
              ],
            },
          ),
        )
        .timeout(deadline);
    final report = AcpPeerReport(
      peer: command.peer,
      protocolVersion: negotiated.protocolVersion,
      stopReason: prompt.stopReason,
      updateCount: client.history.forSession(sessionId).length,
      reverseMethods: List<String>.unmodifiable(reverseMethods),
      artifactSha256s: <String, String>{
        for (final entry in command.artifacts.entries)
          entry.key:
              sha256.convert(File(entry.value).readAsBytesSync()).toString(),
      },
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    await client.close();
    final exitCode = await process.exitCode.timeout(deadline);
    final stderrText = await stderrOutput;
    if (exitCode != 0) {
      throw StateError(
        '${command.peer} exited with $exitCode: ${stderrText.trim()}',
      );
    }
    return report;
  } on Object {
    await client.close();
    if (await _isRunning(process)) {
      process.kill();
      await process.exitCode;
    }
    rethrow;
  }
}

Map<String, String> _sanitizedEnvironment() => <String, String>{
      for (final key in const <String>[
        'PATH',
        'SystemRoot',
        'TEMP',
        'TMP',
        'TMPDIR',
      ])
        if (Platform.environment[key] case final String value) key: value,
    };

Future<bool> _isRunning(Process process) async {
  try {
    await process.exitCode.timeout(Duration.zero);
    return false;
  } on TimeoutException {
    return true;
  }
}

final class _ProcessByteTransport implements ProtocolByteTransport {
  _ProcessByteTransport(this.process);

  final Process process;
  var _closed = false;

  @override
  Stream<List<int>> get incomingBytes => process.stdout;

  @override
  Future<void> sendBytes(List<int> bytes) async {
    if (_closed) {
      throw StateError('ACP peer stdin is closed.');
    }
    process.stdin.add(bytes);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await process.stdin.close();
  }
}
