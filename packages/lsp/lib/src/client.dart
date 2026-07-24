import 'connection.dart';
import 'registration.dart';

/// Small caller-owned facade over one [LspConnection] generation.
final class LspClient {
  LspClient({LspConnection? connection})
      : _connection = connection ?? LspConnection();

  LspConnection _connection;

  LspConnection get connection => _connection;

  void initialize(Map<String, Object?> serverCapabilities) {
    _connection
      ..beginInitialize()
      ..completeInitialize(serverCapabilities)
      ..sendInitialized();
  }

  LspPendingRequest request(String method) => _connection.beginRequest(method);

  void complete(int requestId, {Object? failure}) =>
      _connection.completeRequest(requestId, failure: failure);

  void register(LspDynamicRegistration registration) =>
      _connection.registerCapability(registration);

  void unregister(String registrationId) =>
      _connection.unregisterCapability(registrationId);

  void reconnect() {
    _connection = _connection.reconnect();
  }
}
