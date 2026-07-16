import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('generateSpeech', () {
    test('text/options/headers/cancellation 透传给 doGenerate', () async {
      final model = _ScriptedSpeechModel(
        result: contracts.SpeechModelResult(
          audio: Uint8List.fromList([1, 2, 3]),
          warnings: const [],
        ),
      );
      final controller = contracts.CancellationController();

      await generateSpeech(
        model: model,
        text: 'hello world',
        voice: 'nova',
        outputFormat: 'wav',
        instructions: 'Speak calmly.',
        speed: 1.2,
        language: 'en',
        providerOptions: const {
          'openai': {'speed': 1.2},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(received.text, 'hello world');
      expect(received.voice, 'nova');
      expect(received.outputFormat, 'wav');
      expect(received.instructions, 'Speak calmly.');
      expect(received.speed, 1.2);
      expect(received.language, 'en');
      expect(received.providerOptions, {
        'openai': {'speed': 1.2},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('result 原样映射并把单次 response 包成 responses', () async {
      final records = captureWarningLogs();
      final audio = Uint8List.fromList([1, 2, 3]);
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'tts-1',
        headers: const {'content-type': 'audio/wav'},
        body: audio,
      );
      final model = _ScriptedSpeechModel(
        result: contracts.SpeechModelResult(
          audio: audio,
          warnings: const [contracts.OtherWarning('note')],
          providerMetadata: const {
            'openai': {'requestId': 'req-1'},
          },
          response: response,
        ),
      );

      final result = await generateSpeech(
        model: model,
        text: 'hello world',
        outputFormat: 'wav',
      );

      expect(result.audio, audio);
      expect(result.mediaType, 'audio/wav');
      expect(result.format, 'wav');
      expect(result.warnings, [const contracts.OtherWarning('note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (test.speech / test-speech-model): note',
      ]);
      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
      expect(result.responses, [response]);
    });

    test('generic binary content-type 不覆盖请求的音频格式', () async {
      final audio = Uint8List.fromList([1, 2, 3]);
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'tts-1',
        headers: const {'content-type': 'application/octet-stream'},
        body: audio,
      );
      final model = _ScriptedSpeechModel(
        result: contracts.SpeechModelResult(
          audio: audio,
          warnings: const [],
          response: response,
        ),
      );

      final result = await generateSpeech(
        model: model,
        text: 'hello world',
        outputFormat: 'wav',
      );

      expect(result.mediaType, 'audio/wav');
      expect(result.format, 'wav');
    });

    test('content-type header lookup is case-insensitive', () async {
      final audio = Uint8List.fromList([1, 2, 3]);
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'tts-1',
        headers: const {'CONTENT-TYPE': 'audio/mpeg; charset=binary'},
        body: audio,
      );
      final model = _ScriptedSpeechModel(
        result: contracts.SpeechModelResult(
          audio: audio,
          warnings: const [],
          response: response,
        ),
      );

      final result = await generateSpeech(
        model: model,
        text: 'hello world',
        outputFormat: 'wav',
      );

      expect(result.mediaType, 'audio/mpeg');
      expect(result.format, 'mp3');
    });

    test('model result format 覆盖不可信响应头与原始请求格式', () async {
      final audio = Uint8List.fromList([1, 2, 3]);
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'tts-1',
        headers: const {'content-type': 'application/octet-stream'},
        body: audio,
      );
      final model = _ScriptedSpeechModel(
        result: contracts.SpeechModelResult(
          audio: audio,
          format: 'mp3',
          warnings: const [],
          response: response,
        ),
      );

      final result = await generateSpeech(
        model: model,
        text: 'hello world',
        outputFormat: 'ogg',
      );

      expect(result.mediaType, 'audio/mp3');
      expect(result.format, 'mp3');
    });

    test('空 audio 抛 NoSpeechGeneratedError', () async {
      final model = _ScriptedSpeechModel(
        result: SpeechModelResult(audio: Uint8List(0), warnings: const []),
      );

      await expectLater(
        generateSpeech(model: model, text: 'hello'),
        throwsA(isA<contracts.NoSpeechGeneratedError>()),
      );
    });
  });
}

final class _ScriptedSpeechModel implements contracts.SpeechModel {
  _ScriptedSpeechModel({required this.result});

  final contracts.SpeechModelResult result;
  final List<contracts.SpeechModelCallOptions> receivedCallOptions = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.speech';

  @override
  String get modelId => 'test-speech-model';

  @override
  Future<contracts.SpeechModelResult> doGenerate(
    contracts.SpeechModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return result;
  }
}
