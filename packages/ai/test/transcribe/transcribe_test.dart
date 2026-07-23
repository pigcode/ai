import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('transcribe', () {
    test('DataBytes/providerOptions/headers/cancellation 透传给 doGenerate',
        () async {
      final model = _ScriptedTranscriptionModel(
        result: const contracts.TranscriptionModelResult(
          text: 'hello world',
          segments: [],
          warnings: [],
        ),
      );
      final bytes = Uint8List.fromList([1, 2, 3]);
      final controller = contracts.CancellationController();

      await transcribe(
        model: model,
        audio: DataBytes(bytes),
        mediaType: 'audio/wav',
        providerOptions: const {
          'openai': {'language': 'en'},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(
          (received.audio as contracts.TranscriptionAudioBytes).bytes, bytes);
      expect(received.mediaType, 'audio/wav');
      expect(received.providerOptions, {
        'openai': {'language': 'en'},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('DataBase64 透传为 TranscriptionAudioBase64', () async {
      final model = _ScriptedTranscriptionModel(
        result: const contracts.TranscriptionModelResult(
          text: 'hello world',
          segments: [],
          warnings: [],
        ),
      );
      final base64Audio = base64Encode([1, 2, 3]);

      await transcribe(
        model: model,
        audio: DataBase64(base64Audio),
        mediaType: 'audio/mp3',
      );

      final received = model.receivedCallOptions.single;
      expect(
        (received.audio as contracts.TranscriptionAudioBase64).base64,
        base64Audio,
      );
      expect(received.mediaType, 'audio/mp3');
    });

    test('DataText 音频输入会被拒绝', () async {
      final model = _ScriptedTranscriptionModel(
        result: const contracts.TranscriptionModelResult(
          text: 'unused',
          segments: [],
          warnings: [],
        ),
      );

      await expectLater(
        transcribe(
          model: model,
          audio: const DataText('not audio'),
          mediaType: 'text/plain',
        ),
        throwsA(isA<contracts.InvalidArgumentError>()),
      );
      expect(model.receivedCallOptions, isEmpty);
    });

    test('result 原样映射并把单次 response 包成 responses', () async {
      final records = captureWarningLogs();
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'whisper-1',
        headers: const {'x-request-id': 'req-1'},
        body: const {'text': 'hello world'},
      );
      final model = _ScriptedTranscriptionModel(
        result: contracts.TranscriptionModelResult(
          text: 'hello world',
          segments: const [
            contracts.TranscriptionSegment(
              text: 'hello',
              startSecond: 0,
              endSecond: 1.2,
            ),
          ],
          language: 'en',
          durationInSeconds: 1.2,
          warnings: const [contracts.OtherWarning('note')],
          providerMetadata: const {
            'openai': {'requestId': 'req-1'},
          },
          response: response,
        ),
      );

      final result = await transcribe(
        model: model,
        audio: DataBytes(Uint8List.fromList([1])),
        mediaType: 'audio/wav',
      );

      expect(result.text, 'hello world');
      expect(result.segments.single.text, 'hello');
      expect(result.language, 'en');
      expect(result.durationInSeconds, 1.2);
      expect(result.warnings, [const contracts.OtherWarning('note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning '
            '(test.transcription / test-transcription-model): note',
      ]);
      expect(result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
      expect(result.responses, [response]);
    });

    test('空 transcript 抛 NoTranscriptGeneratedError', () async {
      final model = _ScriptedTranscriptionModel(
        result: const contracts.TranscriptionModelResult(
          text: '',
          segments: [],
          warnings: [],
        ),
      );

      await expectLater(
        transcribe(
          model: model,
          audio: DataBytes(Uint8List.fromList([1])),
          mediaType: 'audio/wav',
        ),
        throwsA(isA<contracts.NoTranscriptGeneratedError>()),
      );
    });
  });

  group('streamTranscribe', () {
    test('透传流式参数并聚合最终 transcript 结果', () async {
      final records = captureWarningLogs();
      final response = contracts.ResponseInfo(
        timestamp: DateTime.utc(2026),
        modelId: 'stream-model',
        headers: const {'x-request-id': 'req-1'},
        body: const {'initial': true},
      );
      final expectedResponse = contracts.ResponseInfo(
        id: 'stream-response',
        timestamp: DateTime.utc(2026),
        modelId: 'stream-model-live',
        headers: const {'x-request-id': 'req-2'},
        body: const {'final': true},
      );
      final model = _ScriptedStreamableTranscriptionModel(
        result: contracts.TranscriptionModelStreamResult(
          response: response,
          stream: Stream<contracts.TranscriptionModelStreamPart>.fromIterable(
            const [
              contracts.TranscriptionStreamStart([
                contracts.OtherWarning('note'),
              ]),
              contracts.TranscriptionDelta(id: 'd1', delta: 'hel'),
              contracts.TranscriptionPartial(
                id: 'p1',
                text: 'hello wor',
                startSecond: 0,
                durationInSeconds: 0.8,
                channelIndex: 1,
              ),
              contracts.TranscriptionFinal(
                id: 'f1',
                text: 'hello world',
                startSecond: 0,
                endSecond: 1,
              ),
              contracts.TranscriptionRaw({'event': 'raw'}),
              contracts.TranscriptionResponseMetadata(
                contracts.ResponseInfo(
                  id: 'stream-response',
                  modelId: 'stream-model-live',
                ),
              ),
              contracts.TranscriptionResponseMetadata(
                contracts.ResponseInfo(
                  headers: {'x-request-id': 'req-2'},
                  body: {'final': true},
                ),
              ),
              contracts.TranscriptionFinish(
                text: 'hello world',
                segments: [
                  contracts.TranscriptionSegment(
                    text: 'hello world',
                    startSecond: 0,
                    endSecond: 1,
                  ),
                ],
                language: 'en',
                durationInSeconds: 1,
                providerMetadata: {
                  'openai': {'requestId': 'req-1'},
                },
              ),
            ],
          ),
        ),
      );
      final controller = contracts.CancellationController();
      final firstBytes = Uint8List.fromList([1, 2, 3]);

      final result = streamTranscribe(
        model: model,
        audio: Stream<DataContent>.fromIterable([
          DataBytes(firstBytes),
          const DataBase64('BAUG'),
        ]),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
          rate: 24000,
        ),
        providerOptions: const {
          'openai': {'language': 'en'},
        },
        headers: const {'x-custom': 'v'},
        include: const StreamTranscriptionInclude(rawChunks: true),
        cancellation: controller.signal,
      );

      final parts = await result.stream.toList();

      expect(model.receivedStreamOptions, hasLength(1));
      final received = model.receivedStreamOptions.single;
      expect(received.inputAudioFormat.type, 'audio/pcm');
      expect(received.inputAudioFormat.rate, 24000);
      expect(received.providerOptions, {
        'openai': {'language': 'en'},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.includeRawChunks, isTrue);
      expect(received.cancellation, same(controller.signal));
      final receivedAudio = await received.audio.toList();
      expect((receivedAudio[0] as contracts.TranscriptionAudioBytes).bytes,
          firstBytes);
      expect(
        (receivedAudio[1] as contracts.TranscriptionAudioBase64).base64,
        'BAUG',
      );

      expect(
        parts,
        const [
          TranscriptDeltaPart(id: 'd1', delta: 'hel'),
          TranscriptPartialPart(
            id: 'p1',
            text: 'hello wor',
            startSecond: 0,
            durationInSeconds: 0.8,
            channelIndex: 1,
          ),
          TranscriptFinalPart(
            id: 'f1',
            text: 'hello world',
            startSecond: 0,
            endSecond: 1,
          ),
          TranscriptionRawPart({'event': 'raw'}),
        ],
      );
      expect(await result.text, 'hello world');
      expect((await result.segments).single.text, 'hello world');
      expect(await result.language, 'en');
      expect(await result.durationInSeconds, 1);
      expect(await result.warnings, const [contracts.OtherWarning('note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning '
            '(test.transcription / test-stream-transcription-model): note',
      ]);
      expect(await result.responses, [expectedResponse]);
      expect(await result.providerMetadata, {
        'openai': {'requestId': 'req-1'},
      });
    });

    test('DataText 流式音频输入会被映射流拒绝', () async {
      final model = _ScriptedStreamableTranscriptionModel(
        result: contracts.TranscriptionModelStreamResult(
          stream: Stream<contracts.TranscriptionModelStreamPart>.fromIterable(
            const [
              contracts.TranscriptionFinish(text: 'done', segments: []),
            ],
          ),
        ),
      );

      final result = streamTranscribe(
        model: model,
        audio: Stream<DataContent>.fromIterable(const [DataText('not audio')]),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
      );
      await result.stream.drain<void>();

      await expectLater(
        model.receivedStreamOptions.single.audio.toList(),
        throwsA(isA<contracts.InvalidArgumentError>()),
      );
    });

    test('provider 错误分块会终止 stream 并让聚合 Future 失败', () async {
      final error = StateError('provider failed');
      final model = _ScriptedStreamableTranscriptionModel(
        result: contracts.TranscriptionModelStreamResult(
          stream: Stream<contracts.TranscriptionModelStreamPart>.fromIterable([
            const contracts.TranscriptionDelta(delta: 'partial'),
            contracts.TranscriptionStreamError(error),
            const contracts.TranscriptionFinish(text: 'ignored', segments: []),
          ]),
        ),
      );

      final result = streamTranscribe(
        model: model,
        audio: const Stream<DataContent>.empty(),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
      );

      final parts = await result.stream.toList();

      expect(
        parts,
        [
          const TranscriptDeltaPart(delta: 'partial'),
          TranscriptionErrorPart(error),
        ],
      );
      await expectLater(result.text, throwsA(same(error)));
      await expectLater(result.segments, throwsA(same(error)));
    });

    test('provider stream 抛错会作为终端错误分块发出', () async {
      final error = StateError('stream failed');
      final model = _ScriptedStreamableTranscriptionModel(
        result: contracts.TranscriptionModelStreamResult(
          stream: Stream<contracts.TranscriptionModelStreamPart>.error(error),
        ),
      );

      final result = streamTranscribe(
        model: model,
        audio: const Stream<DataContent>.empty(),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
      );

      final parts = await result.stream.toList();

      expect(parts, [TranscriptionErrorPart(error)]);
      await expectLater(result.text, throwsA(same(error)));
    });

    test('consumeStream 消费公开流并等待最终结果', () async {
      final model = _ScriptedStreamableTranscriptionModel(
        result: contracts.TranscriptionModelStreamResult(
          stream: Stream<contracts.TranscriptionModelStreamPart>.fromIterable(
            const <contracts.TranscriptionModelStreamPart>[
              contracts.TranscriptionDelta(delta: 'hel'),
              contracts.TranscriptionFinish(
                text: 'hello',
                segments: <contracts.TranscriptionSegment>[],
              ),
            ],
          ),
        ),
      );
      final result = streamTranscribe(
        model: model,
        audio: const Stream<DataContent>.empty(),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
      );

      await result.consumeStream();

      expect(await result.text, 'hello');
      expect(await result.segments, isEmpty);
    });

    test('cancellation interrupts a provider stream that ignores the signal',
        () async {
      final streamStarted = Completer<void>();
      final model = _IdleStreamableTranscriptionModel(streamStarted);
      final cancellation = contracts.CancellationController();
      final reason = StateError('transcription cancelled');
      final result = streamTranscribe(
        model: model,
        audio: const Stream<DataContent>.empty(),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
        cancellation: cancellation.signal,
      );
      final partsFuture = result.stream.toList();
      await streamStarted.future;

      cancellation.cancel(reason);
      final parts = await partsFuture;

      expect(parts, <TranscriptionStreamPart>[
        TranscriptionErrorPart(reason),
      ]);
      await expectLater(result.text, throwsA(same(reason)));
      expect(model.receivedCancellation, same(cancellation.signal));
    });

    test('doStream 抛错会作为终端错误分块发出', () async {
      final error = StateError('doStream failed');
      final model = _ThrowingStreamableTranscriptionModel(error);

      final result = streamTranscribe(
        model: model,
        audio: const Stream<DataContent>.empty(),
        inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
          type: 'audio/pcm',
        ),
      );

      final parts = await result.stream.toList();

      expect(parts, [TranscriptionErrorPart(error)]);
      await expectLater(result.text, throwsA(same(error)));
    });

    test('普通 transcription model 不支持 streamTranscribe', () {
      final model = _ScriptedTranscriptionModel(
        result: const contracts.TranscriptionModelResult(
          text: 'hello',
          segments: [],
          warnings: [],
        ),
      );

      expect(
        () => streamTranscribe(
          model: model,
          audio: const Stream<DataContent>.empty(),
          inputAudioFormat: const contracts.TranscriptionInputAudioFormat(
            type: 'audio/pcm',
          ),
        ),
        throwsA(isA<contracts.UnsupportedFunctionalityError>()),
      );
    });
  });
}

final class _ScriptedTranscriptionModel
    implements contracts.TranscriptionModel {
  _ScriptedTranscriptionModel({required this.result});

  final contracts.TranscriptionModelResult result;
  final List<contracts.TranscriptionModelCallOptions> receivedCallOptions = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.transcription';

  @override
  String get modelId => 'test-transcription-model';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return result;
  }
}

final class _ScriptedStreamableTranscriptionModel
    implements contracts.StreamableTranscriptionModel {
  _ScriptedStreamableTranscriptionModel({required this.result});

  final contracts.TranscriptionModelStreamResult result;
  final List<contracts.TranscriptionModelStreamOptions> receivedStreamOptions =
      [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.transcription';

  @override
  String get modelId => 'test-stream-transcription-model';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) async {
    return const contracts.TranscriptionModelResult(
      text: 'unused',
      segments: [],
      warnings: [],
    );
  }

  @override
  Future<contracts.TranscriptionModelStreamResult> doStream(
    contracts.TranscriptionModelStreamOptions options,
  ) async {
    receivedStreamOptions.add(options);
    return result;
  }
}

final class _ThrowingStreamableTranscriptionModel
    implements contracts.StreamableTranscriptionModel {
  _ThrowingStreamableTranscriptionModel(this.error);

  final Object error;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.transcription';

  @override
  String get modelId => 'test-throwing-stream-transcription-model';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) async {
    return const contracts.TranscriptionModelResult(
      text: 'unused',
      segments: [],
      warnings: [],
    );
  }

  @override
  Future<contracts.TranscriptionModelStreamResult> doStream(
    contracts.TranscriptionModelStreamOptions options,
  ) async {
    throw error;
  }
}

final class _IdleStreamableTranscriptionModel
    implements contracts.StreamableTranscriptionModel {
  _IdleStreamableTranscriptionModel(this.streamStarted);

  final Completer<void> streamStarted;
  contracts.CancellationSignal? receivedCancellation;

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.transcription';

  @override
  String get modelId => 'test-idle-stream-transcription-model';

  @override
  Future<contracts.TranscriptionModelResult> doGenerate(
    contracts.TranscriptionModelCallOptions options,
  ) async =>
      const contracts.TranscriptionModelResult(
        text: 'unused',
        segments: <contracts.TranscriptionSegment>[],
        warnings: <contracts.Warning>[],
      );

  @override
  Future<contracts.TranscriptionModelStreamResult> doStream(
    contracts.TranscriptionModelStreamOptions options,
  ) async {
    receivedCancellation = options.cancellation;
    Stream<contracts.TranscriptionModelStreamPart> idle() async* {
      streamStarted.complete();
      await Completer<void>().future;
    }

    return contracts.TranscriptionModelStreamResult(
      stream: idle(),
    );
  }
}
