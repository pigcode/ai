import 'dart:async';
import 'dart:isolate';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

final class FileStoreCoordinatorCapability {
  const FileStoreCoordinatorCapability({
    required this.port,
    required this.canonicalRoot,
    required this.nonce,
  });

  final SendPort port;
  final String canonicalRoot;
  final String nonce;

  FileStoreCoordinatorClient connect({
    String? expectedCanonicalRoot,
    String? expectedNonce,
  }) =>
      FileStoreCoordinatorClient._(
        port: port,
        canonicalRoot: expectedCanonicalRoot ?? canonicalRoot,
        nonce: expectedNonce ?? nonce,
      );
}

final class FileStoreCoordinatorClient {
  const FileStoreCoordinatorClient._({
    required SendPort port,
    required this.canonicalRoot,
    required String nonce,
  })  : _port = port,
        _nonce = nonce;

  final SendPort _port;
  final String canonicalRoot;
  final String _nonce;

  Future<T> synchronized<T>(
    Future<T> Function() action, {
    required Duration timeout,
  }) async {
    final response = ReceivePort();
    final requestId =
        '${DateTime.now().microsecondsSinceEpoch}-${response.sendPort.hashCode}';
    _port.send(<String, Object?>{
      'op': 'acquire',
      'requestId': requestId,
      'root': canonicalRoot,
      'nonce': _nonce,
      'reply': response.sendPort,
    });
    late final Object? message;
    try {
      message = await response.first.timeout(timeout);
    } on TimeoutException {
      _port.send(<String, Object?>{
        'op': 'cancel',
        'requestId': requestId,
        'root': canonicalRoot,
        'nonce': _nonce,
      });
      throw const AgentStoreException(
        AgentStoreErrorCode.storeBusy,
        'Timed out waiting for the process Store coordinator.',
      );
    } finally {
      response.close();
    }
    if (message is! Map<Object?, Object?> || message['ok'] != true) {
      final code = message is Map<Object?, Object?>
          ? message['code']
          : 'coordinationRequired';
      throw AgentStoreException(
        code == 'storeBusy'
            ? AgentStoreErrorCode.storeBusy
            : AgentStoreErrorCode.coordinationRequired,
        'Store coordinator rejected the client capability.',
      );
    }
    final lease = message['lease'];
    if (lease is! String) {
      throw const AgentStoreException(
        AgentStoreErrorCode.coordinationRequired,
        'Store coordinator returned an invalid lease.',
      );
    }
    try {
      return await action();
    } finally {
      _port.send(<String, Object?>{
        'op': 'release',
        'lease': lease,
        'root': canonicalRoot,
        'nonce': _nonce,
      });
    }
  }
}
