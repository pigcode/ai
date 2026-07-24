import 'connection.dart';

/// Small transport-independent facade over Analysis Server connection state.
final class AnalysisServerClient {
  AnalysisServerClient({AnalysisServerConnection? connection})
      : _connection = connection ?? AnalysisServerConnection();

  AnalysisServerConnection _connection;

  AnalysisServerConnection get connection => _connection;

  AnalysisServerPendingRequest beginVersionQuery() =>
      _connection.beginVersionQuery();

  void completeVersionQuery(
    String requestId,
    Map<String, Object?> result, {
    Map<String, Object?> clientCapabilities = const <String, Object?>{},
  }) =>
      _connection.completeVersionQuery(
        requestId,
        result,
        clientCapabilities: clientCapabilities,
      );

  AnalysisServerPendingRequest request(
    String method, {
    Map<String, Object?>? params,
  }) =>
      _connection.beginRequest(method, params: params);

  void complete({
    required String id,
    required String method,
    Object? result,
    Object? failure,
  }) =>
      _connection.completeResponse(
        id: id,
        method: method,
        result: result,
        failure: failure,
      );

  AnalysisServerPendingRequest cancel(String requestId) =>
      _connection.beginCancel(requestId);

  AnalysisServerPendingRequest shutdown() => _connection.beginShutdown();

  AnalysisServerNotificationRecord receiveNotification(
    String event,
    Map<String, Object?> params,
  ) =>
      _connection.receiveNotification(event, params);

  void close() => _connection.close();

  AnalysisServerConnection reconnect() {
    _connection = _connection.reconnect();
    return _connection;
  }
}
