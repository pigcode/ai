import 'dart:io';

import '../http/endpoint.dart';

/// Bridges caller-owned `dart:io` requests to a framework-neutral endpoint.
///
/// The adapter never binds or closes an [HttpServer].
final class McpIoHttpServerAdapter {
  const McpIoHttpServerAdapter(this.endpoint);

  final McpHttpEndpoint endpoint;

  Future<void> handle(HttpRequest request) async {
    final headers = <String, String>{};
    request.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    final response = await endpoint.handle(
      McpHttpEndpointRequest(
        method: request.method,
        uri: request.uri,
        headers: headers,
        body: request,
        remoteAddress: request.connectionInfo?.remoteAddress.address,
      ),
    );
    request.response.statusCode = response.statusCode;
    for (final entry in response.headers.entries) {
      request.response.headers.set(entry.key, entry.value);
    }
    await request.response.addStream(response.body);
    await request.response.close();
  }
}
