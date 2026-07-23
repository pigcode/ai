import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(
  Object body, {
  int statusCode = 200,
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(jsonEncode(body))),
    statusCode,
    headers: const {'content-type': 'application/json'},
  );
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.response);

  final http.StreamedResponse response;
  final List<http.BaseRequest> requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    return response;
  }
}

AnthropicConfig _config(
  http.Client client, {
  String name = 'anthropic.messages',
}) {
  return AnthropicConfig(
    providerName: name,
    baseUrl: 'https://api.anthropic.com/v1',
    headers: () => <String, String>{
      'x-api-key': 'test-key',
      'anthropic-version': '2023-06-01',
      'Anthropic-Beta': 'custom-beta, FILES-API-2025-04-14',
    },
    client: client,
  );
}

void main() {
  // Compatibility fixture (unit): P1-ANTHROPIC-08
  group('AnthropicFiles', () {
    test('uploads a multipart file and returns canonical metadata', () async {
      const createdAt = '2025-04-14T12:34:56Z';
      final client = _RecordingClient(
        _jsonResponse(<String, Object?>{
          'id': 'file_abc',
          'type': 'file',
          'filename': 'note.txt',
          'mime_type': 'text/plain',
          'size_bytes': 5,
          'created_at': createdAt,
          'downloadable': false,
          'scope': <String, Object?>{
            'type': 'session',
            'id': 'session_1',
            'future_field': 'ignored',
          },
        }),
      );
      final files = AnthropicFiles(config: _config(client));

      final result = await files.uploadFile(
        const FilesUploadOptions(
          data: FileDataText('hello'),
          mediaType: 'text/plain',
          filename: 'note.txt',
        ),
      );

      final request = client.requests.single as http.MultipartRequest;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.anthropic.com/v1/files');
      expect(request.headers['x-api-key'], 'test-key');
      expect(request.headers['anthropic-version'], '2023-06-01');

      final betaHeaderKeys = request.headers.keys
          .where((header) => header.toLowerCase() == anthropicBetaHeaderName)
          .toList();
      expect(betaHeaderKeys, <String>['anthropic-beta']);
      final betas = request.headers['anthropic-beta']!.split(',');
      expect(betas, hasLength(2));
      expect(
        betas.toSet(),
        <String>{'custom-beta', 'files-api-2025-04-14'},
      );

      final part = request.files.single;
      expect(part.field, 'file');
      expect(part.filename, 'note.txt');
      expect(part.contentType.toString(), 'text/plain');
      expect(await part.finalize().toBytes(), utf8.encode('hello'));

      expect(files.provider, 'anthropic.files');
      expect(result.providerReference, <String, String>{
        'anthropic': 'file_abc',
      });
      expect(result.mediaType, 'text/plain');
      expect(result.filename, 'note.txt');
      expect(result.providerMetadata, <String, JsonObject>{
        'anthropic': <String, Object?>{
          'filename': 'note.txt',
          'mimeType': 'text/plain',
          'sizeBytes': 5,
          'createdAt': createdAt,
          'downloadable': false,
          'scope': <String, Object?>{
            'type': 'session',
            'id': 'session_1',
          },
        },
      });
      expect(result.warnings, isEmpty);
    });

    test('uses blob filename and omits absent optional metadata', () async {
      const createdAt = '2025-04-15T00:00:00Z';
      final client = _RecordingClient(
        _jsonResponse(<String, Object?>{
          'id': 'file_blob',
          'type': 'file',
          'filename': 'blob',
          'mime_type': 'application/octet-stream',
          'size_bytes': 1,
          'created_at': createdAt,
        }),
      );
      final files = AnthropicFiles(config: _config(client));

      final result = await files.uploadFile(
        FilesUploadOptions(
          data: FileDataBytes(Uint8List.fromList(<int>[1])),
          mediaType: 'application/octet-stream',
        ),
      );

      final request = client.requests.single as http.MultipartRequest;
      final part = request.files.single;
      expect(part.filename, 'blob');
      expect(await part.finalize().toBytes(), <int>[1]);
      expect(result.providerMetadata, <String, JsonObject>{
        'anthropic': <String, Object?>{
          'filename': 'blob',
          'mimeType': 'application/octet-stream',
          'sizeBytes': 1,
          'createdAt': createdAt,
        },
      });
      final metadata = result.providerMetadata!['anthropic']!;
      expect(metadata.containsKey('downloadable'), isFalse);
      expect(metadata.containsKey('scope'), isFalse);
    });

    test('normalizes integer-valued size bytes from JSON numbers', () async {
      final client = _RecordingClient(
        _jsonResponse(<String, Object?>{
          'id': 'file_abc',
          'type': 'file',
          'filename': 'note.txt',
          'mime_type': 'text/plain',
          'size_bytes': 5.0,
          'created_at': '2025-04-15T00:00:00Z',
        }),
      );
      final files = AnthropicFiles(config: _config(client));

      final result = await files.uploadFile(
        const FilesUploadOptions(
          data: FileDataText('hello'),
          mediaType: 'text/plain',
        ),
      );

      expect(result.providerMetadata!['anthropic']!['sizeBytes'], 5);
    });

    test('rejects unsupported data and invalid media type before sending',
        () async {
      final client = _RecordingClient(
        _jsonResponse(<String, Object?>{
          'id': 'unused',
          'type': 'file',
          'filename': 'unused',
          'mime_type': 'text/plain',
          'size_bytes': 1,
          'created_at': '2025-04-15T00:00:00Z',
        }),
      );
      final files = AnthropicFiles(config: _config(client));

      await expectLater(
        files.uploadFile(
          FilesUploadOptions(
            data: FileDataUrl(Uri.parse('https://example.com/file.txt')),
            mediaType: 'text/plain',
          ),
        ),
        throwsA(
          isA<InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'data'),
        ),
      );
      await expectLater(
        files.uploadFile(
          FilesUploadOptions(
            data: FileDataBytes(Uint8List.fromList(<int>[1])),
            mediaType: 'not a media type',
          ),
        ),
        throwsA(
          isA<InvalidArgumentError>()
              .having((error) => error.argument, 'argument', 'mediaType'),
        ),
      );

      expect(client.requests, isEmpty);
    });

    test('maps official non-2xx errors to ApiCallError', () async {
      final client = _RecordingClient(
        _jsonResponse(
          <String, Object?>{
            'type': 'error',
            'error': <String, Object?>{
              'type': 'invalid_request_error',
              'message': 'invalid file',
            },
          },
          statusCode: 400,
        ),
      );
      final files = AnthropicFiles(config: _config(client));

      await expectLater(
        files.uploadFile(
          const FilesUploadOptions(
            data: FileDataText('hello'),
            mediaType: 'text/plain',
          ),
        ),
        throwsA(
          isA<ApiCallError>()
              .having((error) => error.statusCode, 'statusCode', 400)
              .having((error) => error.message, 'message', 'invalid file'),
        ),
      );
    });

    test('rejects success responses missing required fields', () async {
      final client = _RecordingClient(
        _jsonResponse(<String, Object?>{
          'id': 'file_abc',
          'type': 'file',
          'filename': 'note.txt',
          'mime_type': 'text/plain',
          'created_at': '2025-04-15T00:00:00Z',
        }),
      );
      final files = AnthropicFiles(config: _config(client));

      await expectLater(
        files.uploadFile(
          const FilesUploadOptions(
            data: FileDataText('hello'),
            mediaType: 'text/plain',
          ),
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });
}
