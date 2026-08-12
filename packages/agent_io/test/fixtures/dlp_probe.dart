import 'dart:convert';
import 'dart:io';

const _fixtureSecret = 'pigcode-fixture-credential-8472';

Future<void> main(List<String> arguments) async {
  if (arguments.isEmpty) {
    exitCode = 64;
    return;
  }
  try {
    switch (arguments[0]) {
      case 'tcp':
        final socket = await Socket.connect(
          arguments[1],
          int.parse(arguments[2]),
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        exit(0);
      case 'tcp-secret':
        final socket = await Socket.connect(
          arguments[1],
          int.parse(arguments[2]),
          timeout: const Duration(seconds: 2),
        );
        socket.write(arguments[3]);
        await socket.flush();
        await socket.close();
        exit(0);
      case 'scan-secret':
        final environmentLeak = Platform.environment.values
            .any((value) => value.contains(_fixtureSecret));
        var workspaceLeak = false;
        await for (final entity in Directory.current.list(recursive: true)) {
          if (entity is! File) continue;
          try {
            if ((await entity.readAsString()).contains(_fixtureSecret)) {
              workspaceLeak = true;
              break;
            }
          } on FileSystemException {
            // An unreadable file is not visible credential material.
          }
        }
        stdout.writeln(
          environmentLeak || workspaceLeak ? 'SECRET_VISIBLE' : 'SECRET_ABSENT',
        );
        exit(environmentLeak || workspaceLeak ? 78 : 0);
      case 'udp':
        final socket = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          0,
        );
        final address = (await InternetAddress.lookup(arguments[1])).first;
        final sent = socket.send(
          const <int>[1],
          address,
          int.parse(arguments[2]),
        );
        socket.close();
        if (sent != 1) throw StateError('UDP send rejected');
        exit(0);
      case 'dns':
        final addresses = await InternetAddress.lookup(arguments[1]);
        if (addresses.isEmpty) throw StateError('DNS returned no addresses');
        exit(0);
      case 'unix':
        final socket = await Socket.connect(
          InternetAddress(arguments[1], type: InternetAddressType.unix),
          0,
          timeout: const Duration(seconds: 2),
        );
        socket.destroy();
        exit(0);
      case 'frame':
        final body = utf8.encode(
          '{"authorization":"Bearer boundary-sensitive-value","safe":true}',
        );
        stdout.add(
          <int>[
            ...ascii.encode('Content-Length: ${body.length}\r\n\r\n'),
            ...body,
          ],
        );
        await stdout.flush();
        exit(0);
      default:
        exitCode = 64;
        return;
    }
  } on Object catch (error) {
    stderr.writeln(error);
    exit(77);
  }
}
