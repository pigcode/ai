import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  try {
    final uriLine = await stdin
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .first;
    final result = await _run(Uri.parse(uriLine));
    stdout.writeln(jsonEncode(result));
  } on Object catch (error) {
    stderr.writeln('DTD client fixture failed (${error.runtimeType}).');
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _run(Uri uri) async {
  final ownerSocket = await WebSocket.connect(uri.toString());
  final callerSocket = await WebSocket.connect(uri.toString());
  final owner = _JsonSocket(ownerSocket);
  final caller = _JsonSocket(callerSocket);
  final scenarios = <String>[];
  final errorCodes = <int>{};
  try {
    await owner.request(
      id: 'owner-listen',
      method: 'streamListen',
      params: const <String, Object?>{'streamId': 'PigcodeMatrix'},
    );
    await caller.request(
      id: 'caller-post',
      method: 'postEvent',
      params: const <String, Object?>{
        'streamId': 'PigcodeMatrix',
        'eventKind': 'matrixEvent',
        'eventData': <String, Object?>{'value': 1},
      },
    );
    final notification = await owner.next();
    if (notification['method'] != 'streamNotify' ||
        (notification['params'] as Map<String, Object?>?)?['eventKind'] !=
            'matrixEvent') {
      throw StateError('DTD stream notification was not forwarded.');
    }
    await owner.request(
      id: 'owner-cancel',
      method: 'streamCancel',
      params: const <String, Object?>{'streamId': 'PigcodeMatrix'},
    );
    scenarios.add('stream');

    await owner.request(
      id: 'owner-register',
      method: 'registerService',
      params: const <String, Object?>{
        'service': 'PigcodeMatrix',
        'method': 'echo',
      },
    );
    caller.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': 'caller-service',
      'method': 'PigcodeMatrix.echo',
      'params': const <String, Object?>{'value': 2},
    });
    final forwarded = await owner.next();
    if (forwarded['method'] != 'PigcodeMatrix.echo' ||
        forwarded['id'] == null) {
      throw StateError('DTD service call was not forwarded.');
    }
    owner.send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': forwarded['id'],
      'result': const <String, Object?>{'value': 3},
    });
    final serviceResponse = await caller.nextForId('caller-service');
    if ((serviceResponse['result'] as Map<String, Object?>?)?['value'] != 3) {
      throw StateError('DTD service response was not returned.');
    }
    scenarios.add('service');

    final denied = await caller.request(
      id: 'caller-read-denied',
      method: 'FileSystem.readFileAsString',
      params: const <String, Object?>{
        'uri': 'file:///__pigcode_dtd_matrix_outside__/missing.txt',
      },
      allowError: true,
    );
    final deniedCode = _errorCode(denied);
    if (deniedCode != 142) {
      throw StateError('DTD FileSystem read was not denied.');
    }
    errorCodes.add(deniedCode);
    scenarios.add('fileSystemDenied');

    final invalidSecret = await caller.request(
      id: 'caller-roots-denied',
      method: 'FileSystem.setIDEWorkspaceRoots',
      params: const <String, Object?>{
        'secret': 'deliberately-invalid',
        'roots': <Object?>['file:///tmp/'],
      },
      allowError: true,
    );
    final secretCode = _errorCode(invalidSecret);
    if (secretCode != 142) {
      throw StateError('DTD invalid workspace secret was not denied.');
    }
    errorCodes.add(secretCode);
    scenarios.add('invalidRootSecret');

    return <String, Object?>{
      'scenarios': scenarios,
      'observedErrorCodes': errorCodes.toList()..sort(),
    };
  } finally {
    await owner.close();
    await caller.close();
  }
}

int _errorCode(Map<String, Object?> envelope) {
  final error = envelope['error'];
  if (error is! Map<String, Object?> || error['code'] is! int) {
    throw StateError('DTD response did not contain an error code.');
  }
  return error['code']! as int;
}

final class _JsonSocket {
  _JsonSocket(this.socket)
      : _messages = StreamIterator<Map<String, Object?>>(
          socket.map((message) {
            if (message is! String) {
              throw StateError('DTD WebSocket message must be text.');
            }
            final decoded = jsonDecode(message);
            if (decoded is! Map<String, Object?>) {
              throw StateError('DTD WebSocket message must be an object.');
            }
            return decoded;
          }),
        );

  final WebSocket socket;
  final StreamIterator<Map<String, Object?>> _messages;

  void send(Map<String, Object?> envelope) {
    socket.add(jsonEncode(envelope));
  }

  Future<Map<String, Object?>> request({
    required String id,
    required String method,
    required Map<String, Object?> params,
    bool allowError = false,
  }) async {
    send(<String, Object?>{
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final response = await nextForId(id);
    if (!allowError && response['error'] != null) {
      throw StateError('DTD request returned an error.');
    }
    return response;
  }

  Future<Map<String, Object?>> nextForId(String id) async {
    while (true) {
      final message = await next();
      if (message['id'] == id && message['method'] == null) {
        return message;
      }
      throw StateError('DTD client received an unexpected message.');
    }
  }

  Future<Map<String, Object?>> next() async {
    if (!await _messages.moveNext()) {
      throw StateError('DTD WebSocket closed before the expected message.');
    }
    return _messages.current;
  }

  Future<void> close() async {
    await socket.close();
    await _messages.cancel();
  }
}
