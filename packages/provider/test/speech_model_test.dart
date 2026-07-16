import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('SpeechModelCallOptions', () {
    test('holds text and optional fields', () {
      final signal = CancellationController().signal;
      final options = SpeechModelCallOptions(
        text: 'hello world',
        voice: 'nova',
        outputFormat: 'wav',
        instructions: 'Speak calmly.',
        speed: 1.2,
        language: 'en',
        headers: const {'x-a': '1'},
        providerOptions: const {
          'openai': {'instructions': 'provider instruction'},
        },
        cancellation: signal,
      );

      expect(options.text, 'hello world');
      expect(options.voice, 'nova');
      expect(options.outputFormat, 'wav');
      expect(options.instructions, 'Speak calmly.');
      expect(options.speed, 1.2);
      expect(options.language, 'en');
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'openai': {'instructions': 'provider instruction'},
      });
      expect(options.cancellation, same(signal));
    });

    test('equality ignores cancellation identity', () {
      final a = SpeechModelCallOptions(
        text: 'hello',
        cancellation: CancellationController().signal,
      );
      final b = SpeechModelCallOptions(
        text: 'hello',
        cancellation: CancellationController().signal,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SpeechModelResult', () {
    test('carries audio, warnings, metadata, request, and response', () {
      final audio = Uint8List.fromList([1, 2, 3]);
      final timestamp = DateTime.utc(2026);
      final result = SpeechModelResult(
        audio: audio,
        format: 'mp3',
        warnings: const [OtherWarning('note')],
        providerMetadata: const {
          'openai': {'requestId': 'req-1'},
        },
        request: const RequestInfo(body: 'json'),
        response: ResponseInfo(
          timestamp: timestamp,
          modelId: 'tts-1',
          headers: const {'x-request-id': 'req-1'},
          body: audio,
        ),
      );

      expect(result.audio, audio);
      expect(result.format, 'mp3');
      expect(result.warnings.single, isA<OtherWarning>());
      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
      expect(result.request?.body, 'json');
      expect(result.response?.timestamp, timestamp);
    });
  });

  group('SpeechModel interface shape', () {
    test('a minimal fake implementation satisfies the interface', () async {
      final model = _FakeSpeechModel();

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'fake.speech');
      expect(model.modelId, 'fake-model');

      final result = await model.doGenerate(
        const SpeechModelCallOptions(text: 'hello'),
      );
      expect(result.audio, [1, 2, 3]);
    });
  });
}

final class _FakeSpeechModel implements SpeechModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.speech';

  @override
  String get modelId => 'fake-model';

  @override
  Future<SpeechModelResult> doGenerate(
    SpeechModelCallOptions options,
  ) async {
    return SpeechModelResult(
      audio: Uint8List.fromList([1, 2, 3]),
      warnings: const [],
    );
  }
}
