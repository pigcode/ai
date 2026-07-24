import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';

void main() {
  final connection = DapConnection();
  final initialize = connection.beginInitialize();

  // Send the initialize request with a caller-owned adapter transport.
  connection.completeInitialize(
    initialize.seq,
    const <String, Object?>{'supportsCompletionsRequest': true},
  );
  print(
    'request ${initialize.seq}: ${initialize.command}; '
    'completions=${connection.capabilities.supportsCommand('completions')}',
  );
}
