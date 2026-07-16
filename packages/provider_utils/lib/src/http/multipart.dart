import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;

import 'http.dart';

/// Sends a multipart POST and dispatches its response through shared handlers.
///
/// An injected client remains caller-owned; an internally created client is
/// closed after the response handler completes. Request cancellation and
/// transport-error behavior match the shared JSON transport helpers.
Future<T> postMultipartToApi<T>({
  required Uri url,
  Map<String, String>? headers,
  required void Function(http.MultipartRequest request) build,
  required ResponseHandler<T> successHandler,
  required FailedResponseHandler failureHandler,
  http.Client? client,
  CancellationSignal? cancellation,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();

  try {
    final request = http.AbortableMultipartRequest(
      'POST',
      url,
      abortTrigger: cancellation?.whenCancelled,
    )..headers.addAll(headers ?? const <String, String>{});
    build(request);

    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request);
    } catch (error) {
      if (error is http.RequestAbortedException) {
        rethrow;
      }
      throw mapTransportError(error, url: url);
    }

    final context = ResponseContext(url: url, response: response);
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        return await successHandler(context);
      } on http.RequestAbortedException {
        rethrow;
      } on http.ClientException catch (error) {
        throw mapTransportError(error, url: url);
      } on TimeoutException catch (error) {
        throw mapTransportError(error, url: url);
      }
    }
    throw await failureHandler(context);
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

/// Converts inline [FileData] variants to bytes for multipart requests.
///
/// URL and provider-reference variants require provider-specific resolution
/// and therefore fail with [InvalidArgumentError].
Uint8List fileDataToBytes(FileData data, {required String argument}) {
  return switch (data) {
    FileDataBytes(:final bytes) => bytes,
    FileDataBase64(:final base64) => base64Decode(base64),
    FileDataText(:final text) => Uint8List.fromList(utf8.encode(text)),
    FileDataUrl() || FileDataReference() => throw InvalidArgumentError(
        argument: argument,
        message: '$argument must be FileDataBytes, FileDataBase64, or '
            'FileDataText.',
      ),
  };
}
