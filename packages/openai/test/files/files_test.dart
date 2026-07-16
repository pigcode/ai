import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _jsonResponse(String body) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

final class _RecordingMultipartClient extends http.BaseClient {
  _RecordingMultipartClient(this.body);

  final String body;
  http.MultipartRequest? lastRequest;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request as http.MultipartRequest;
    return _jsonResponse(body);
  }
}

OpenAiConfig _config(http.Client client, {String providerName = 'openai'}) {
  return OpenAiConfig(
    providerName: providerName,
    baseUrl: 'https://api.openai.com/v1',
    headers: () => {'Authorization': 'Bearer test-key'},
    client: client,
  );
}

String _successBody() {
  return jsonEncode({
    'id': 'file-abc',
    'object': 'file',
    'bytes': 12,
    'created_at': 123,
    'filename': 'note.txt',
    'purpose': 'assistants',
    'status': 'processed',
    'expires_at': 456,
  });
}

void main() {
  group('OpenAiFiles', () {
    test('uploads multipart file to /files', () async {
      final client = _RecordingMultipartClient(_successBody());
      final files = OpenAiFiles(config: _config(client));

      final result = await files.uploadFile(
        const FilesUploadOptions(
          data: FileDataText('hello'),
          mediaType: 'text/plain',
          filename: 'note.txt',
          providerOptions: {
            'openai': {'purpose': 'assistants', 'expiresAfter': 3600},
          },
        ),
      );

      final request = client.lastRequest!;
      expect(request.method, 'POST');
      expect(request.url.toString(), 'https://api.openai.com/v1/files');
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(request.fields, {
        'purpose': 'assistants',
        'expires_after[anchor]': 'created_at',
        'expires_after[seconds]': '3600',
      });
      expect(request.files.single.field, 'file');
      expect(request.files.single.filename, 'note.txt');
      expect(request.files.single.contentType.toString(), 'text/plain');
      expect(await request.files.single.finalize().toBytes(),
          utf8.encode('hello'));

      expect(result.providerReference, {'openai': 'file-abc'});
      expect(result.mediaType, 'text/plain');
      expect(result.filename, 'note.txt');
      expect(result.providerMetadata, {
        'openai': {
          'filename': 'note.txt',
          'purpose': 'assistants',
          'bytes': 12,
          'createdAt': 123,
          'status': 'processed',
          'expiresAt': 456,
        },
      });
      expect(result.warnings, isEmpty);
    });

    test('uses derived provider metadata key for Azure-style names', () async {
      final client = _RecordingMultipartClient(_successBody());
      final files = OpenAiFiles(
        config: _config(client, providerName: 'azure-openai'),
      );

      final result = await files.uploadFile(
        FilesUploadOptions(
          data: FileDataBytes(Uint8List.fromList([1, 2, 3])),
          mediaType: 'application/octet-stream',
        ),
      );

      expect(files.provider, 'azure-openai.files');
      expect(client.lastRequest!.files.single.filename, 'blob');
      expect(result.providerReference, {'azure': 'file-abc'});
      expect(result.providerMetadata!.containsKey('openai'), isFalse);
      expect(result.providerMetadata!['azure'], isNotNull);
    });
  });
}
