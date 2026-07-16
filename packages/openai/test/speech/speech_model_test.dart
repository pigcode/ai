import 'dart:convert';

import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;
import 'package:test/test.dart';

http.StreamedResponse _binaryResponse(
  List<int> bytes, {
  int statusCode = 200,
  Map<String, String> headers = const {'content-type': 'audio/mpeg'},
  String reasonPhrase = '',
}) {
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    headers: headers,
    reasonPhrase: reasonPhrase,
  );
}

http.StreamedResponse _jsonResponse(
  String body, {
  int statusCode = 200,
  Map<String, String> headers = const {'content-type': 'application/json'},
}) {
  return http.StreamedResponse(
    Stream.value(utf8.encode(body)),
    statusCode,
    headers: headers,
  );
}

final class _RecordingClient extends http.BaseClient {
  _RecordingClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
      handler;

  http.BaseRequest? lastRequest;
  Object? lastBody;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastRequest = request;
    if (request is http.Request) {
      lastBody = jsonDecode(request.body);
    }
    return handler(request);
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

void main() {
  group('OpenAiSpeechModel — 基础字段', () {
    test('provider/modelId/specificationVersion', () {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'openai.speech');
      expect(model.modelId, 'tts-1');
      expect(model, isA<SpeechModel>());
    });
  });

  group('OpenAiSpeechModel.doGenerate — 请求侧', () {
    test('发送 JSON 到 /audio/speech', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model =
          OpenAiSpeechModel('gpt-4o-mini-tts', config: _config(client));

      await model.doGenerate(
        const SpeechModelCallOptions(
          text: 'hello world',
          voice: 'nova',
          outputFormat: 'wav',
          instructions: 'Speak calmly.',
          speed: 1.2,
          headers: {'x-custom': 'v'},
        ),
      );

      expect(
        client.lastRequest!.url.toString(),
        'https://api.openai.com/v1/audio/speech',
      );
      expect(client.lastRequest!.method, 'POST');
      expect(client.lastRequest!.headers['Authorization'], 'Bearer test-key');
      expect(client.lastRequest!.headers['x-custom'], 'v');
      expect(client.lastBody, {
        'model': 'gpt-4o-mini-tts',
        'input': 'hello world',
        'voice': 'nova',
        'response_format': 'wav',
        'speed': 1.2,
        'instructions': 'Speak calmly.',
      });
    });

    test('默认 voice/outputFormat 使用 alloy/mp3', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      await model.doGenerate(const SpeechModelCallOptions(text: 'hello'));

      expect(client.lastBody, {
        'model': 'tts-1',
        'input': 'hello',
        'voice': 'alloy',
        'response_format': 'mp3',
      });
    });

    test('unsupported language is ignored with a warning', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      final result = await model.doGenerate(
        const SpeechModelCallOptions(text: 'hello', language: 'en'),
      );

      expect((client.lastBody! as Map<String, Object?>).containsKey('language'),
          isFalse);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
      expect(
          (result.warnings.single as UnsupportedWarning).feature, 'language');
    });

    test('unsupported outputFormat falls back to mp3 with a warning', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      final result = await model.doGenerate(
        const SpeechModelCallOptions(text: 'hello', outputFormat: 'ogg'),
      );

      expect(
          (client.lastBody! as Map<String, Object?>)['response_format'], 'mp3');
      expect(result.format, 'mp3');
      expect(result.warnings.single, isA<UnsupportedWarning>());
      expect(
        (result.warnings.single as UnsupportedWarning).feature,
        'outputFormat',
      );
    });

    test('legacy TTS ignores direct instructions with a warning', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      final result = await model.doGenerate(
        const SpeechModelCallOptions(
          text: 'hello',
          instructions: 'Speak warmly.',
        ),
      );

      expect(
          (client.lastBody! as Map<String, Object?>)
              .containsKey('instructions'),
          isFalse);
      expect(result.warnings.single, isA<UnsupportedWarning>());
      expect((result.warnings.single as UnsupportedWarning).feature,
          'instructions');
    });

    test('legacy TTS ignores provider instructions with a warning', () async {
      final client =
          _RecordingClient((request) async => _binaryResponse([1, 2, 3]));
      final model = OpenAiSpeechModel('tts-1-hd', config: _config(client));

      final result = await model.doGenerate(
        const SpeechModelCallOptions(
          text: 'hello',
          providerOptions: {
            'openai': {'instructions': 'Speak warmly.'},
          },
        ),
      );

      expect(
          (client.lastBody! as Map<String, Object?>)
              .containsKey('instructions'),
          isFalse);
      expect(result.warnings.single, isA<UnsupportedWarning>());
      expect((result.warnings.single as UnsupportedWarning).feature,
          'instructions');
    });
  });

  group('OpenAiSpeechModel.doGenerate — 响应侧', () {
    test('成功响应解码 audio 与 response', () async {
      final client = _RecordingClient(
        (request) async => _binaryResponse(
          [1, 2, 3],
          headers: {
            'content-type': 'audio/wav',
            'x-request-id': 'req-1',
          },
        ),
      );
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      final result = await model.doGenerate(
        const SpeechModelCallOptions(text: 'hello', outputFormat: 'wav'),
      );

      expect(result.audio, [1, 2, 3]);
      expect(result.warnings, isEmpty);
      expect(result.request!.body, jsonEncode(client.lastBody));
      expect(result.response!.modelId, 'tts-1');
      expect(result.response!.headers!['x-request-id'], 'req-1');
      expect(result.response!.body, [1, 2, 3]);
    });

    test('错误响应经 openAiFailedResponseHandler 抛 ApiCallError', () async {
      final client = _RecordingClient(
        (request) async => _jsonResponse(
          '{"error":{"message":"bad speech"}}',
          statusCode: 400,
          headers: const {'content-type': 'application/json'},
        ),
      );
      final model = OpenAiSpeechModel('tts-1', config: _config(client));

      await expectLater(
        model.doGenerate(const SpeechModelCallOptions(text: 'hello')),
        throwsA(
          isA<ApiCallError>()
              .having((e) => e.message, 'message', 'bad speech')
              .having((e) => e.statusCode, 'statusCode', 400),
        ),
      );
    });
  });
}
