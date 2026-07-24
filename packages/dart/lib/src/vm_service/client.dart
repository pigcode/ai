import 'connection.dart';
import 'streams.dart';

final class VmServiceClient {
  factory VmServiceClient({
    VmServiceConnection? connection,
    int maxStreamEvents = 1024,
  }) {
    final activeConnection = connection ?? VmServiceConnection();
    return VmServiceClient._(
      connection: activeConnection,
      streams: VmServiceStreams(
        connection: activeConnection,
        maxEvents: maxStreamEvents,
      ),
      maxStreamEvents: maxStreamEvents,
    );
  }

  const VmServiceClient._({
    required this.connection,
    required this.streams,
    required int maxStreamEvents,
  }) : _maxStreamEvents = maxStreamEvents;

  final VmServiceConnection connection;
  final VmServiceStreams streams;
  final int _maxStreamEvents;

  VmServicePendingRequest request(
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
  }

  void close() {
    if (connection.lifecycle == VmServiceConnectionLifecycle.closed) {
      return;
    }
    connection.close();
    streams.disconnect();
  }

  VmServiceClient reconnect() {
    close();
    return VmServiceClient(maxStreamEvents: _maxStreamEvents);
  }
}
