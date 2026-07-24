import 'dart:async';
import 'dart:isolate';
import 'dart:math';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'file_store_coordinator_protocol.dart';
import 'store_layout.dart';

final class FileStoreCoordinator {
  FileStoreCoordinator._({
    required this.capability,
    required Isolate isolate,
  }) : _isolate = isolate;

  final FileStoreCoordinatorCapability capability;
  final Isolate _isolate;
  bool _closed = false;

  static Future<FileStoreCoordinator> start(StoreLayout layout) async {
    final bootstrap = ReceivePort();
    final nonce = _secureNonce();
    final isolate = await Isolate.spawn<List<Object?>>(
      _coordinatorMain,
      <Object?>[bootstrap.sendPort, layout.root.path, nonce],
      debugName: 'pigcode-file-store-coordinator',
    );
    final port = await bootstrap.first;
    bootstrap.close();
    if (port is! SendPort) {
      isolate.kill(priority: Isolate.immediate);
      throw const AgentStoreException(
        AgentStoreErrorCode.coordinationRequired,
        'Store coordinator failed to start.',
      );
    }
    return FileStoreCoordinator._(
      capability: FileStoreCoordinatorCapability(
        port: port,
        canonicalRoot: layout.root.path,
        nonce: nonce,
      ),
      isolate: isolate,
    );
  }

  FileStoreCoordinatorClient get client => capability.connect();

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    final response = ReceivePort();
    capability.port.send(<String, Object?>{
      'op': 'close',
      'root': capability.canonicalRoot,
      'nonce': capability.nonce,
      'reply': response.sendPort,
    });
    try {
      await response.first.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      // The isolate is killed below even when it cannot acknowledge shutdown.
    } finally {
      response.close();
      _isolate.kill(priority: Isolate.immediate);
    }
  }
}

void _coordinatorMain(List<Object?> bootstrap) {
  final parent = bootstrap[0]! as SendPort;
  final root = bootstrap[1]! as String;
  final nonce = bootstrap[2]! as String;
  final requests = ReceivePort();
  parent.send(requests.sendPort);
  final queue = <Map<Object?, Object?>>[];
  String? activeLease;
  String? activeRequestId;
  var leaseCounter = 0;

  void grantNext() {
    if (activeLease != null || queue.isEmpty) return;
    final request = queue.removeAt(0);
    final reply = request['reply'];
    if (reply is! SendPort) return;
    activeRequestId = request['requestId']! as String;
    activeLease = '${++leaseCounter}-$activeRequestId';
    reply.send(<String, Object?>{
      'ok': true,
      'lease': activeLease,
    });
  }

  requests.listen((Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final reply = raw['reply'];
    final matches = raw['root'] == root && raw['nonce'] == nonce;
    if (!matches) {
      if (reply is SendPort) {
        reply.send(<String, Object?>{
          'ok': false,
          'code': 'coordinationRequired',
        });
      }
      return;
    }
    switch (raw['op']) {
      case 'acquire':
        queue.add(raw);
        grantNext();
      case 'cancel':
        queue.removeWhere(
          (request) => request['requestId'] == raw['requestId'],
        );
        if (activeRequestId == raw['requestId']) {
          activeLease = null;
          activeRequestId = null;
          grantNext();
        }
      case 'release':
        if (raw['lease'] == activeLease) {
          activeLease = null;
          activeRequestId = null;
          grantNext();
        }
      case 'close':
        if (reply is SendPort) {
          reply.send(<String, Object?>{'ok': true});
        }
        requests.close();
        Isolate.exit();
    }
  });
}

String _secureNonce() {
  final random = Random.secure();
  final output = StringBuffer();
  for (var index = 0; index < 32; index++) {
    output.write(random.nextInt(256).toRadixString(16).padLeft(2, '0'));
  }
  return output.toString();
}
