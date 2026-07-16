import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('generateVideo', () {
    test('prompt/options/inputs/headers/cancellation 透传给 doGenerate', () async {
      final model = _ScriptedVideoModel(
        resultForCall: (options, index) async => contracts.VideoModelResult(
          videos: [
            contracts.VideoModelVideoDataBytes(
              Uint8List.fromList(_mp4Bytes),
            ),
          ],
          warnings: const [],
        ),
      );
      final controller = contracts.CancellationController();
      const image = contracts.VideoModelFileBase64(
        'aW1hZ2U=',
        mediaType: 'image/png',
      );
      final frameImages = [
        contracts.VideoFrameImage(
          image: contracts.VideoModelFileUrl(
            Uri.parse('https://example.com/first.png'),
            mediaType: 'image/png',
          ),
          frameType: contracts.VideoFrameType.firstFrame,
        ),
      ];
      final inputReferences = [
        contracts.VideoModelFileUrl(Uri.parse('https://example.com/ref.png')),
      ];

      await generateVideo(
        model: model,
        prompt: 'make a city timelapse',
        n: 1,
        aspectRatio: '16:9',
        resolution: '1080p',
        duration: 5,
        fps: 24,
        seed: 42,
        image: image,
        frameImages: frameImages,
        inputReferences: inputReferences,
        generateAudio: true,
        providerOptions: const {
          'google': {'enhancePrompt': true},
        },
        headers: const {'x-custom': 'v'},
        cancellation: controller.signal,
      );

      expect(model.receivedCallOptions, hasLength(1));
      final received = model.receivedCallOptions.single;
      expect(received.prompt, 'make a city timelapse');
      expect(received.n, 1);
      expect(received.aspectRatio, '16:9');
      expect(received.resolution, '1080p');
      expect(received.duration, 5);
      expect(received.fps, 24);
      expect(received.seed, 42);
      expect(received.image, image);
      expect(received.frameImages, frameImages);
      expect(received.inputReferences, inputReferences);
      expect(received.generateAudio, isTrue);
      expect(received.providerOptions, {
        'google': {'enhancePrompt': true},
      });
      expect(received.headers, {'x-custom': 'v'});
      expect(received.cancellation, same(controller.signal));
    });

    test('按 maxVideosPerCall 分批并聚合结果', () async {
      final records = captureWarningLogs();
      final responses = [
        contracts.ResponseInfo(
          modelId: 'video-model',
          timestamp: DateTime.utc(2026, 1),
        ),
        contracts.ResponseInfo(
          modelId: 'video-model',
          timestamp: DateTime.utc(2026, 2),
        ),
        contracts.ResponseInfo(
          modelId: 'video-model',
          timestamp: DateTime.utc(2026, 3),
        ),
      ];
      final model = _ScriptedVideoModel(
        maxVideosPerCallValue: 2,
        resultForCall: (options, index) async {
          return contracts.VideoModelResult(
            videos: [
              for (var i = 0; i < options.n; i++)
                contracts.VideoModelVideoDataBytes(
                  Uint8List.fromList([index, i]),
                  mediaType: 'video/mp4',
                ),
            ],
            warnings: [contracts.OtherWarning('warning-$index')],
            providerMetadata: {
              'test': {
                'call$index': options.n,
                'videos': [
                  for (var i = 0; i < options.n; i++) {'call': index, 'i': i},
                ],
              },
            },
            response: responses[index - 1],
          );
        },
      );

      final result = await generateVideo(
        model: model,
        prompt: 'make five cuts',
        n: 5,
      );

      expect(
        model.receivedCallOptions.map((options) => options.n),
        [2, 2, 1],
      );
      expect(
        result.videos.map((video) {
          final data = video.data as contracts.FileDataBytes;
          return data.bytes.toList();
        }),
        [
          [1, 0],
          [1, 1],
          [2, 0],
          [2, 1],
          [3, 0],
        ],
      );
      expect(
        (result.video.data as contracts.FileDataBytes).bytes.toList(),
        [1, 0],
      );
      expect(result.warnings, [
        const contracts.OtherWarning('warning-1'),
        const contracts.OtherWarning('warning-2'),
        const contracts.OtherWarning('warning-3'),
      ]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (test.video / test-video-model): warning-1',
        'Pigcode AI Warning (test.video / test-video-model): warning-2',
        'Pigcode AI Warning (test.video / test-video-model): warning-3',
      ]);
      expect(result.responses, responses);
      expect(result.providerMetadata, {
        'test': {
          'call1': 2,
          'call2': 2,
          'call3': 1,
          'videos': [
            {'call': 1, 'i': 0},
            {'call': 1, 'i': 1},
            {'call': 2, 'i': 0},
            {'call': 2, 'i': 1},
            {'call': 3, 'i': 0},
          ],
        },
      });
    });

    test('保留 bytes/base64/url 视频数据并解析 mediaType 与 format', () async {
      final movUrl = Uri.parse('https://example.com/out.mov');
      final aviUrl = Uri.parse('https://example.com/out.avi');
      final ogvUrl = Uri.parse('https://example.com/out.ogv');
      final model = _ScriptedVideoModel(
        maxVideosPerCallValue: 8,
        resultForCall: (options, index) async => contracts.VideoModelResult(
          videos: [
            contracts.VideoModelVideoDataBytes(Uint8List.fromList(_mp4Bytes)),
            contracts.VideoModelVideoDataBytes(Uint8List.fromList(_webmBytes)),
            contracts.VideoModelVideoDataBytes(Uint8List.fromList(_movBytes)),
            const contracts.VideoModelVideoDataBase64(
              'dm1wNA==',
              mediaType: 'video/mp4',
            ),
            contracts.VideoModelVideoDataBase64(base64Encode(_webmBytes)),
            contracts.VideoModelVideoDataUrl(
              movUrl,
              mediaType: 'video/quicktime',
            ),
            contracts.VideoModelVideoDataUrl(aviUrl),
            contracts.VideoModelVideoDataUrl(ogvUrl),
          ],
          warnings: const [],
        ),
      );

      final result = await generateVideo(
        model: model,
        prompt: 'render mixed formats',
        n: 8,
      );

      expect(
        result.videos.map((video) => video.mediaType),
        [
          'video/mp4',
          'video/webm',
          'video/quicktime',
          'video/mp4',
          'video/webm',
          'video/quicktime',
          'video/x-msvideo',
          'video/ogg',
        ],
      );
      expect(
        result.videos.map((video) => video.format),
        ['mp4', 'webm', 'quicktime', 'mp4', 'webm', 'quicktime', 'avi', 'ogg'],
      );
      expect(result.videos[0].data, isA<contracts.FileDataBytes>());
      expect(result.videos[1].data, isA<contracts.FileDataBytes>());
      expect(result.videos[2].data, isA<contracts.FileDataBytes>());
      expect(
        (result.videos[3].data as contracts.FileDataBase64).base64,
        'dm1wNA==',
      );
      expect(
        (result.videos[4].data as contracts.FileDataBase64).base64,
        base64Encode(_webmBytes),
      );
      expect((result.videos[5].data as contracts.FileDataUrl).url, movUrl);
      expect((result.videos[6].data as contracts.FileDataUrl).url, aviUrl);
      expect((result.videos[7].data as contracts.FileDataUrl).url, ogvUrl);
    });

    test('模型未声明 maxVideosPerCall 时默认每次生成 1 个', () async {
      final model = _ScriptedVideoModel(
        resultForCall: (options, index) async => contracts.VideoModelResult(
          videos: [
            for (var i = 0; i < options.n; i++)
              contracts.VideoModelVideoDataBytes(
                Uint8List.fromList([index, i]),
              ),
          ],
          warnings: const [],
        ),
      );

      await generateVideo(
        model: model,
        prompt: 'make three clips',
        n: 3,
      );

      expect(
        model.receivedCallOptions.map((options) => options.n),
        [1, 1, 1],
      );
    });

    test('空 videos 抛 NoVideoGeneratedError 并保留 responses', () async {
      const response = contracts.ResponseInfo(modelId: 'video-model');
      final model = _ScriptedVideoModel(
        resultForCall: (options, index) async =>
            const contracts.VideoModelResult(
          videos: [],
          warnings: [],
          response: response,
        ),
      );

      await expectLater(
        generateVideo(model: model, prompt: 'make nothing'),
        throwsA(
          isA<contracts.NoVideoGeneratedError>()
              .having((error) => error.responses, 'responses', [response]),
        ),
      );
    });
  });
}

final class _ScriptedVideoModel implements contracts.VideoModel {
  _ScriptedVideoModel({
    required this.resultForCall,
    this.maxVideosPerCallValue,
  });

  final Future<contracts.VideoModelResult> Function(
    contracts.VideoModelCallOptions options,
    int callIndex,
  ) resultForCall;
  final int? maxVideosPerCallValue;
  final List<contracts.VideoModelCallOptions> receivedCallOptions = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'test.video';

  @override
  String get modelId => 'test-video-model';

  @override
  FutureOr<int?> get maxVideosPerCall => maxVideosPerCallValue;

  @override
  Future<contracts.VideoModelResult> doGenerate(
    contracts.VideoModelCallOptions options,
  ) async {
    receivedCallOptions.add(options);
    return resultForCall(options, receivedCallOptions.length);
  }
}

const _mp4Bytes = [
  0,
  0,
  0,
  0,
  0x66,
  0x74,
  0x79,
  0x70,
  0x69,
  0x73,
  0x6f,
  0x6d,
];
const _webmBytes = [0x1a, 0x45, 0xdf, 0xa3];
const _movBytes = [
  0x00,
  0x00,
  0x00,
  0x14,
  0x66,
  0x74,
  0x79,
  0x70,
  0x71,
  0x74,
];
