import 'dart:convert';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'tooling_process_harness.dart';

final class LspPeerCommand {
  const LspPeerCommand({
    required this.peer,
    required this.family,
    required this.release,
    required this.process,
    required this.workspaceUri,
    required this.documentUri,
    required this.languageId,
  });

  final String peer;
  final String family;
  final String release;
  final ToolingProcessCommand process;
  final String workspaceUri;
  final String documentUri;
  final String languageId;
}

final class LspPeerReport {
  const LspPeerReport({
    required this.peer,
    required this.family,
    required this.release,
    required this.transport,
    required this.capabilities,
    required this.scenarios,
    required this.elapsedMilliseconds,
  });

  final String peer;
  final String family;
  final String release;
  final String transport;
  final Map<String, Object?> capabilities;
  final List<String> scenarios;
  final int elapsedMilliseconds;

  Map<String, Object?> toJson() => <String, Object?>{
        'peer': peer,
        'family': family,
        'release': release,
        'transport': transport,
        'capabilities': capabilities,
        'scenarios': scenarios,
        'elapsedMilliseconds': elapsedMilliseconds,
      };
}

List<String> validateLspPeerReport(LspPeerReport report) {
  final violations = <String>[];
  if (report.peer.isEmpty || report.family.isEmpty || report.release.isEmpty) {
    violations.add('LSP peer identity is incomplete.');
  }
  if (report.transport != 'stdio-content-length') {
    violations.add('LSP peer transport is not stdio-content-length.');
  }
  if (report.capabilities.isEmpty) {
    violations.add('LSP peer capabilities are empty.');
  }
  for (final required in const <String>[
    'initialize',
    'open',
    'hover',
    'completion',
    'shutdown',
  ]) {
    if (!report.scenarios.contains(required)) {
      violations.add('LSP peer scenario is missing: $required.');
    }
  }
  if (report.elapsedMilliseconds < 0) {
    violations.add('LSP peer duration is invalid.');
  }
  return List<String>.unmodifiable(violations);
}

Future<LspPeerReport> runLspPeer(
  LspPeerCommand command, {
  Duration deadline = const Duration(seconds: 60),
}) async {
  final stopwatch = Stopwatch()..start();
  final process = await ToolingProcessHarness.start(command.process);
  final scenarios = <String>[];
  var completed = false;
  try {
    await process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 1,
      'method': 'initialize',
      'params': <String, Object?>{
        'processId': null,
        'clientInfo': const <String, Object?>{
          'name': 'pigcode-lsp-peer-matrix',
          'version': '1.0.0',
        },
        'rootUri': command.workspaceUri,
        'workspaceFolders': <Object?>[
          <String, Object?>{
            'uri': command.workspaceUri,
            'name': 'fixture',
          },
        ],
        'capabilities': const <String, Object?>{
          'workspace': <String, Object?>{
            'configuration': true,
            'workspaceFolders': true,
          },
          'window': <String, Object?>{'workDoneProgress': true},
          'textDocument': <String, Object?>{
            'publishDiagnostics': <String, Object?>{
              'relatedInformation': true,
            },
            'hover': <String, Object?>{'dynamicRegistration': true},
            'completion': <String, Object?>{
              'dynamicRegistration': true,
              'completionItem': <String, Object?>{
                'snippetSupport': false,
              },
            },
          },
        },
      },
    });
    final initialize = await _waitForResponse(
      process,
      requestId: 1,
      method: 'initialize',
      workspaceUri: command.workspaceUri,
      deadline: deadline,
    );
    final result = initialize['result'];
    if (result is! JsonObject || result['capabilities'] is! JsonObject) {
      throw StateError('LSP peer returned invalid initialize capabilities.');
    }
    final capabilities = freezeJsonObject(
      result['capabilities']! as JsonObject,
    );
    scenarios.add('initialize');

    await process.send(const <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'initialized',
      'params': <String, Object?>{},
    });
    await process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/didOpen',
      'params': <String, Object?>{
        'textDocument': <String, Object?>{
          'uri': command.documentUri,
          'languageId': command.languageId,
          'version': 1,
          'text': command.languageId == 'dart'
              ? 'void main() { print("pigcode"); }\n'
              : 'const value: string = "pigcode";\nvalue;\n',
        },
      },
    });
    scenarios.add('open');

    await _requestDocumentOperation(
      process,
      firstRequestId: 10,
      method: 'textDocument/hover',
      params: <String, Object?>{
        'textDocument': <String, Object?>{'uri': command.documentUri},
        'position': const <String, Object?>{'line': 0, 'character': 6},
      },
      workspaceUri: command.workspaceUri,
      deadline: deadline,
    );
    scenarios.add('hover');

    await _requestDocumentOperation(
      process,
      firstRequestId: 100,
      method: 'textDocument/completion',
      params: <String, Object?>{
        'textDocument': <String, Object?>{'uri': command.documentUri},
        'position': const <String, Object?>{'line': 0, 'character': 6},
      },
      workspaceUri: command.workspaceUri,
      deadline: deadline,
    );
    scenarios.add('completion');

    await process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'method': 'textDocument/didClose',
      'params': <String, Object?>{
        'textDocument': <String, Object?>{'uri': command.documentUri},
      },
    });
    await process.send(const <String, Object?>{
      'jsonrpc': '2.0',
      'id': 200,
      'method': 'shutdown',
    });
    await _waitForResponse(
      process,
      requestId: 200,
      method: 'shutdown',
      workspaceUri: command.workspaceUri,
      deadline: deadline,
    );
    await process.send(const <String, Object?>{
      'jsonrpc': '2.0',
      'method': 'exit',
    });
    scenarios.add('shutdown');
    final exitCode = await process.close(deadline);
    completed = true;
    if (exitCode != 0) {
      throw StateError(
        'LSP peer exited with $exitCode: ${process.boundedStderr}',
      );
    }
    final report = LspPeerReport(
      peer: command.peer,
      family: command.family,
      release: command.release,
      transport: 'stdio-content-length',
      capabilities: capabilities,
      scenarios: List<String>.unmodifiable(scenarios),
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
    );
    final violations = validateLspPeerReport(report);
    if (violations.isNotEmpty) {
      throw StateError(violations.join(' '));
    }
    return report;
  } finally {
    if (!completed) {
      await process.terminate(deadline);
    }
  }
}

Future<void> _requestDocumentOperation(
  ToolingProcessHarness process, {
  required int firstRequestId,
  required String method,
  required JsonObject params,
  required String workspaceUri,
  required Duration deadline,
}) async {
  for (var attempt = 0; attempt < 30; attempt += 1) {
    final requestId = firstRequestId + attempt;
    await process.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': requestId,
      'method': method,
      'params': params,
    });
    final response = await _waitForResponse(
      process,
      requestId: requestId,
      method: method,
      workspaceUri: workspaceUri,
      deadline: deadline,
      allowError: true,
    );
    final error = response['error'];
    if (error == null) {
      return;
    }
    if (error is JsonObject && error['code'] == -32007 && attempt + 1 < 30) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      continue;
    }
    throw StateError(
      'LSP peer returned an error for $method: ${jsonEncode(error)}',
    );
  }
  throw StateError(
    'LSP peer did not analyze the opened document within 3 seconds.',
  );
}

Future<JsonObject> _waitForResponse(
  ToolingProcessHarness process, {
  required int requestId,
  required String method,
  required String workspaceUri,
  required Duration deadline,
  bool allowError = false,
}) async {
  while (true) {
    final envelope = await process.next(deadline);
    if (envelope.containsKey('method') && envelope.containsKey('id')) {
      await _respondToServerRequest(
        process,
        envelope,
        workspaceUri: workspaceUri,
      );
      continue;
    }
    if (envelope['id'] != requestId) {
      continue;
    }
    if (envelope.containsKey('error')) {
      if (allowError) {
        return envelope;
      }
      throw StateError(
        'LSP peer returned an error for $method: ${jsonEncode(envelope['error'])}',
      );
    }
    LspCodec.instance.decode(
      jsonEncode(envelope),
      sender: LspMessageSender.server,
      responseMethod: method,
    );
    return envelope;
  }
}

Future<void> _respondToServerRequest(
  ToolingProcessHarness process,
  JsonObject envelope, {
  required String workspaceUri,
}) async {
  final method = envelope['method']! as String;
  final params = envelope['params'];
  final result = switch (method) {
    'workspace/configuration' => <Object?>[
        for (final _ in ((params as JsonObject)['items']! as List<Object?>))
          null,
      ],
    'workspace/workspaceFolders' => <Object?>[
        <String, Object?>{'uri': workspaceUri, 'name': 'fixture'},
      ],
    _ => null,
  };
  await process.send(<String, Object?>{
    'jsonrpc': '2.0',
    'id': envelope['id'],
    'result': result,
  });
}
