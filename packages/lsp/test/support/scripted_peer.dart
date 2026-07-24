import 'dart:convert';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';

final class LspScriptedPeerReport {
  const LspScriptedPeerReport({
    required this.scenarios,
    required this.finalDocumentText,
    required this.reverseProposalCount,
    required this.lifecycle,
  });

  final List<String> scenarios;
  final String finalDocumentText;
  final int reverseProposalCount;
  final String lifecycle;
}

/// Deterministic in-memory profile spanning the LSP stateful features.
final class LspScriptedPeer {
  Future<LspScriptedPeerReport> run() async {
    final scenarios = <String>[];
    final connection = LspConnection()
      ..beginInitialize()
      ..completeInitialize(<String, Object?>{
        'completionProvider': <String, Object?>{},
        'diagnosticProvider': <String, Object?>{},
        'textDocumentSync': 2,
      })
      ..sendInitialized();
    scenarios.add('initialize');

    final documents = LspDocumentStore(
      connectionId: connection.connectionId,
    );
    final opened = documents.open(
      uri: 'file:///main.dart',
      languageId: 'dart',
      version: 1,
      text: 'void main() {',
    );
    final changed = documents.change(
      uri: opened.uri,
      version: 2,
      changes: const <LspContentChange>[
        LspContentChange(text: 'void main() {}'),
      ],
    );
    scenarios.add('document-sync');

    LspCodec.instance.decode(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'method': 'textDocument/publishDiagnostics',
        'params': <String, Object?>{
          'uri': opened.uri,
          'version': 2,
          'diagnostics': <Object?>[],
        },
      }),
      sender: LspMessageSender.server,
    );
    scenarios.add('diagnostics');

    final completion = connection.beginRequest('textDocument/completion');
    scenarios.add('completion');

    final progress = LspProgressRegistry(
      connectionId: connection.connectionId,
    )
      ..beginWorkDone('index', title: 'Index')
      ..reportWorkDone('index', percentage: 50)
      ..endWorkDone('index');
    if (!progress.workDone('index').ended) {
      throw StateError('Scripted work-done progress did not end.');
    }
    scenarios.add('progress');

    final cancellations = LspCancellationRegistry(
      connectionId: connection.connectionId,
    )..track(requestId: completion.id, method: completion.method);
    cancellations
      ..requestCancel(completion.id)
      ..addPartial(completion.id, const <Object?>[])
      ..completeError(
        completion.id,
        code: -32800,
        message: 'Request cancelled',
      );
    connection.completeRequest(completion.id);
    scenarios.add('cancel');

    connection.registerCapability(
      const LspDynamicRegistration(
        id: 'hover',
        method: 'textDocument/hover',
      ),
    );
    if (!connection.capabilities.supportsMethod('textDocument/hover')) {
      throw StateError('Scripted dynamic registration was not applied.');
    }
    scenarios.add('dynamic-registration');

    var reverseProposalCount = 0;
    final proposals = LspProposalDispatcher()
      ..register('workspace/applyEdit', (proposal) {
        reverseProposalCount += 1;
        return const <String, Object?>{'applied': false};
      });
    await Future<Object?>.value(
      proposals.dispatch(
        'workspace/applyEdit',
        const <String, Object?>{
          'edit': <String, Object?>{'changes': <String, Object?>{}},
        },
      ),
    );
    scenarios.add('reverse-request');

    connection
      ..beginShutdown()
      ..completeShutdown()
      ..sendExit();
    scenarios.add('shutdown');

    return LspScriptedPeerReport(
      scenarios: List<String>.unmodifiable(scenarios),
      finalDocumentText: changed.text,
      reverseProposalCount: reverseProposalCount,
      lifecycle: connection.lifecycle.name,
    );
  }
}
