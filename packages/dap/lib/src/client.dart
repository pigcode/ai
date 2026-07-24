import 'connection.dart';

final class DapClient {
  DapClient({DapConnection? connection})
      : connection = connection ?? DapConnection();

  final DapConnection connection;

  DapPendingRequest request(
    String command, {
    Object? arguments = const <String, Object?>{},
  }) =>
      connection.beginRequest(command, arguments: arguments);

  void complete({required int requestSeq, required String command}) =>
      connection.completeResponse(
        requestSeq: requestSeq,
        command: command,
      );
}
