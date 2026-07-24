import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';

void main() {
  final client = LspClient()
    ..initialize(
      const <String, Object?>{
        'hoverProvider': true,
        'textDocumentSync': 1,
      },
    );
  final hover = client.request('textDocument/hover');

  // Serialize [hover.id] and the request through a caller-owned transport.
  print('request ${hover.id}: ${hover.method}');
  client.complete(hover.id);
}
