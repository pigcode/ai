import 'dart:convert';
import 'dart:io';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.isNotEmpty) {
    stderr.writeln('The fixed DAP peer accepts no arguments.');
    exitCode = 64;
    return;
  }
  final framer = ContentLengthFramer();
  var sequence = 1;
  try {
    await for (final chunk in stdin) {
      for (final body in framer.add(chunk)) {
        final request = jsonDecode(utf8.decode(body)) as Map<String, Object?>;
        final command = request['command']! as String;
        _send(<String, Object?>{
          'seq': sequence++,
          'type': 'response',
          'request_seq': request['seq'],
          'success': true,
          'command': command,
          if (command == 'initialize')
            'body': const <String, Object?>{
              'supportsConfigurationDoneRequest': true,
            },
        });
        if (command == 'launch') {
          _send(<String, Object?>{
            'seq': sequence++,
            'type': 'event',
            'event': 'initialized',
          });
        }
        if (command == 'disconnect') {
          _send(<String, Object?>{
            'seq': sequence++,
            'type': 'event',
            'event': 'terminated',
          });
          return;
        }
      }
    }
    framer.close();
  } on Object catch (error, stackTrace) {
    stderr
      ..writeln('Fixed DAP peer failed: ${error.runtimeType}')
      ..writeln(stackTrace);
    exitCode = 1;
  }
}

void _send(Map<String, Object?> envelope) {
  final body = utf8.encode(jsonEncode(envelope));
  stdout.add(<int>[
    ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
    ...body,
  ]);
}
