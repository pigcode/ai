import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

final List<Object> _retainedObject = <Object>[
  <int>[17, 23, 42],
  <String, Object?>{'fixture': 'vm-service'},
];

Future<void> main() async {
  final service = await Service.getInfo();
  final webSocketUri = service.serverWebSocketUri;
  final isolateId = Service.getIsolateId(Isolate.current);
  final objectId = Service.getObjectId(_retainedObject);
  if (webSocketUri == null || isolateId == null || objectId == null) {
    stderr.writeln('VM Service fixture did not receive service identifiers.');
    exitCode = 1;
    return;
  }

  stdout.writeln(
    jsonEncode(<String, Object?>{
      'event': 'vmService.started',
      'params': <String, Object?>{
        'webSocketUri': webSocketUri.toString(),
        'isolateId': isolateId,
        'objectId': objectId,
      },
    }),
  );

  await for (final line
      in stdin.transform(utf8.decoder).transform(const LineSplitter())) {
    switch (line) {
      case 'event':
        postEvent(
          'pigcode.matrix',
          const <String, Object?>{'fixture': 'vm-service'},
        );
      case 'shutdown':
        return;
      default:
        stderr.writeln('VM Service fixture received an unknown command.');
        exitCode = 1;
        return;
    }
  }
}
