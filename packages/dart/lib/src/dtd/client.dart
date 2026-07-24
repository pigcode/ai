import 'connection.dart';
import 'file_system.dart';
import 'services.dart';
import 'streams.dart';

final class DtdClient {
  factory DtdClient({
    DtdConnection? connection,
    int maxStreamEvents = 1024,
  }) {
    final activeConnection = connection ?? DtdConnection();
    return DtdClient._(
      connection: activeConnection,
      streams: DtdStreams(
        connection: activeConnection,
        maxEvents: maxStreamEvents,
      ),
      services: DtdServices(connection: activeConnection),
      fileSystem: DtdFileSystem(connection: activeConnection),
      maxStreamEvents: maxStreamEvents,
    );
  }

  const DtdClient._({
    required this.connection,
    required this.streams,
    required this.services,
    required this.fileSystem,
    required int maxStreamEvents,
  }) : _maxStreamEvents = maxStreamEvents;

  final DtdConnection connection;
  final DtdStreams streams;
  final DtdServices services;
  final DtdFileSystem fileSystem;
  final int _maxStreamEvents;

  DtdPendingRequest request(
    String method, {
    required Map<String, Object?> params,
  }) =>
      connection.beginRequest(method, params: params);

  void complete({
    required String id,
    required String method,
    Object? result,
    Object? failure,
  }) {
    connection.completeResponse(
      id: id,
      method: method,
      result: result,
      failure: failure,
    );
    streams.complete(id, failure: failure);
    services.complete(id, failure: failure);
  }

  void close() {
    if (connection.lifecycle == DtdConnectionLifecycle.closed) {
      return;
    }
    connection.close();
    streams.disconnect();
    services.disconnect();
  }

  DtdClient reconnect() {
    close();
    return DtdClient(maxStreamEvents: _maxStreamEvents);
  }
}
