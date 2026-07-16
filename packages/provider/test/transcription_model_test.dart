import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('TranscriptionModelCallOptions', () {
    test('holds bytes audio and optional fields', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final signal = CancellationController().signal;
      final options = TranscriptionModelCallOptions(
        audio: TranscriptionAudioBytes(bytes),
        mediaType: 'audio/wav',
        headers: const {'x-a': '1'},
        providerOptions: const {
          'openai': {'language': 'en'},
        },
        cancellation: signal,
      );

      expect((options.audio as TranscriptionAudioBytes).bytes, bytes);
      expect(options.mediaType, 'audio/wav');
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'openai': {'language': 'en'},
      });
      expect(options.cancellation, same(signal));
    });

    test('equality ignores cancellation identity', () {
      final audio = TranscriptionAudioBase64('aGVsbG8=');
      final a = TranscriptionModelCallOptions(
        audio: audio,
        mediaType: 'audio/mp3',
        cancellation: CancellationController().signal,
      );
      final b = TranscriptionModelCallOptions(
        audio: audio,
        mediaType: 'audio/mp3',
        cancellation: CancellationController().signal,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('TranscriptionModelResult', () {
    test('carries transcript data, warnings, metadata, request, and response',
        () {
      final timestamp = DateTime.utc(2026);
      final result = TranscriptionModelResult(
        text: 'hello world',
        segments: const [
          TranscriptionSegment(
            text: 'hello',
            startSecond: 0,
            endSecond: 1.2,
          ),
        ],
        language: 'en',
        durationInSeconds: 1.2,
        warnings: const [OtherWarning('note')],
        providerMetadata: const {
          'openai': {'requestId': 'req-1'},
        },
        request: const RequestInfo(body: 'multipart'),
        response: ResponseInfo(
          timestamp: timestamp,
          modelId: 'whisper-1',
          headers: const {'x-request-id': 'req-1'},
          body: const {'text': 'hello world'},
        ),
      );

      expect(result.text, 'hello world');
      expect(result.segments.single.text, 'hello');
      expect(result.language, 'en');
      expect(result.durationInSeconds, 1.2);
      expect(result.warnings.single, isA<OtherWarning>());
      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
      expect(result.request?.body, 'multipart');
      expect(result.response?.timestamp, timestamp);
    });
  });

  group('TranscriptionModel streaming contract', () {
    test('stream options hold audio stream, format, and optional fields',
        () async {
      final audio = Stream<TranscriptionAudio>.fromIterable([
        TranscriptionAudioBytes(Uint8List.fromList([1, 2, 3])),
        const TranscriptionAudioBase64('BAUG'),
      ]);
      final signal = CancellationController().signal;
      final options = TranscriptionModelStreamOptions(
        audio: audio,
        inputAudioFormat: const TranscriptionInputAudioFormat(
          type: 'audio/pcm',
          rate: 24000,
        ),
        headers: const {'x-a': '1'},
        providerOptions: const {
          'openai': {'language': 'en'},
        },
        includeRawChunks: true,
        cancellation: signal,
      );

      expect(await options.audio.toList(), hasLength(2));
      expect(options.inputAudioFormat.type, 'audio/pcm');
      expect(options.inputAudioFormat.rate, 24000);
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'openai': {'language': 'en'},
      });
      expect(options.includeRawChunks, isTrue);
      expect(options.cancellation, same(signal));
    });

    test('a streamable fake implementation satisfies the interface', () async {
      final model = _FakeStreamableTranscriptionModel();
      final result = await model.doStream(
        TranscriptionModelStreamOptions(
          audio: Stream<TranscriptionAudio>.fromIterable([
            TranscriptionAudioBytes(Uint8List.fromList([1])),
          ]),
          inputAudioFormat: const TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
        ),
      );

      expect(model, isA<TranscriptionModel>());
      expect(result.response?.modelId, 'fake-stream-model');
      expect(
        await result.stream.toList(),
        const [
          TranscriptionStreamStart([]),
          TranscriptionDelta(delta: 'hel'),
          TranscriptionPartial(text: 'hello'),
          TranscriptionFinal(text: 'hello', startSecond: 0, endSecond: 1),
          TranscriptionFinish(
            text: 'hello',
            segments: [
              TranscriptionSegment(
                text: 'hello',
                startSecond: 0,
                endSecond: 1,
              ),
            ],
          ),
        ],
      );
    });
  });

  group('TranscriptionModel interface shape', () {
    test('a minimal fake implementation satisfies the interface', () async {
      final model = _FakeTranscriptionModel();

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'fake.transcription');
      expect(model.modelId, 'fake-model');

      final result = await model.doGenerate(
        TranscriptionModelCallOptions(
          audio: TranscriptionAudioBytes(Uint8List.fromList([1])),
          mediaType: 'audio/wav',
        ),
      );
      expect(result.text, 'ok');
    });
  });
}

final class _FakeStreamableTranscriptionModel
    implements StreamableTranscriptionModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.transcription';

  @override
  String get modelId => 'fake-stream-model';

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) async {
    return const TranscriptionModelResult(
      text: 'ok',
      segments: [],
      warnings: [],
    );
  }

  @override
  Future<TranscriptionModelStreamResult> doStream(
    TranscriptionModelStreamOptions options,
  ) async {
    return TranscriptionModelStreamResult(
      stream: Stream<TranscriptionModelStreamPart>.fromIterable(
        const [
          TranscriptionStreamStart([]),
          TranscriptionDelta(delta: 'hel'),
          TranscriptionPartial(text: 'hello'),
          TranscriptionFinal(text: 'hello', startSecond: 0, endSecond: 1),
          TranscriptionFinish(
            text: 'hello',
            segments: [
              TranscriptionSegment(
                text: 'hello',
                startSecond: 0,
                endSecond: 1,
              ),
            ],
          ),
        ],
      ),
      response: const ResponseInfo(modelId: 'fake-stream-model'),
    );
  }
}

final class _FakeTranscriptionModel implements TranscriptionModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.transcription';

  @override
  String get modelId => 'fake-model';

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) async {
    return const TranscriptionModelResult(
      text: 'ok',
      segments: [],
      warnings: [],
    );
  }
}
