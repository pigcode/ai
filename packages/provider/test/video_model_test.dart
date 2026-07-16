import 'dart:async';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('VideoModelCallOptions', () {
    test('holds prompt, inputs, generation settings, and request options', () {
      final signal = CancellationController().signal;
      final firstFrame = VideoFrameImage(
        image: VideoModelFileBytes(
          Uint8List.fromList([1, 2, 3]),
          mediaType: 'image/png',
        ),
        frameType: VideoFrameType.firstFrame,
      );
      final reference = VideoModelFileUrl(
        Uri.parse('https://example.com/ref.png'),
        mediaType: 'image/png',
      );
      final options = VideoModelCallOptions(
        prompt: 'A kite over the sea',
        n: 2,
        aspectRatio: '16:9',
        resolution: '1920x1080',
        duration: 5,
        fps: 24,
        seed: 42,
        image: const VideoModelFileBase64(
          'AQID',
          mediaType: 'image/png',
        ),
        frameImages: [firstFrame],
        inputReferences: [reference],
        generateAudio: true,
        headers: const {'x-a': '1'},
        providerOptions: const {
          'google': {'personGeneration': 'allow_all'},
        },
        cancellation: signal,
      );

      expect(options.prompt, 'A kite over the sea');
      expect(options.n, 2);
      expect(options.aspectRatio, '16:9');
      expect(options.resolution, '1920x1080');
      expect(options.duration, 5);
      expect(options.fps, 24);
      expect(options.seed, 42);
      expect(options.image, isA<VideoModelFileBase64>());
      expect(options.frameImages, [firstFrame]);
      expect(options.inputReferences, [reference]);
      expect(options.generateAudio, isTrue);
      expect(options.headers, {'x-a': '1'});
      expect(options.providerOptions, {
        'google': {'personGeneration': 'allow_all'},
      });
      expect(options.cancellation, same(signal));
    });

    test('equality ignores cancellation identity', () {
      final a = VideoModelCallOptions(
        prompt: 'hello',
        cancellation: CancellationController().signal,
      );
      final b = VideoModelCallOptions(
        prompt: 'hello',
        cancellation: CancellationController().signal,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('VideoModelResult', () {
    test('carries videos, warnings, metadata, request, and response', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final timestamp = DateTime.utc(2026);
      final result = VideoModelResult(
        videos: [
          VideoModelVideoDataBytes(bytes, mediaType: 'video/mp4'),
          const VideoModelVideoDataBase64('AAAA', mediaType: 'video/mp4'),
          VideoModelVideoDataUrl(
            Uri.parse('https://example.com/video.mp4'),
            mediaType: 'video/mp4',
          ),
        ],
        warnings: const [OtherWarning('note')],
        providerMetadata: const {
          'google': {
            'videos': [
              {'duration': 5}
            ],
          },
        },
        request: const RequestInfo(body: 'json'),
        response: ResponseInfo(
          timestamp: timestamp,
          modelId: 'veo',
          headers: const {'x-request-id': 'req-1'},
          body: {'ok': true},
        ),
      );

      expect(result.videos, hasLength(3));
      expect(result.videos.first, isA<VideoModelVideoDataBytes>());
      expect(result.warnings.single, isA<OtherWarning>());
      expect(result.providerMetadata, {
        'google': {
          'videos': [
            {'duration': 5}
          ],
        },
      });
      expect(result.request?.body, 'json');
      expect(result.response?.timestamp, timestamp);
    });
  });

  group('VideoModel interface shape', () {
    test('a minimal fake implementation satisfies the interface', () async {
      final model = _FakeVideoModel();

      expect(model.specificationVersion, 'v4');
      expect(model.provider, 'fake.video');
      expect(model.modelId, 'fake-video-model');
      expect(await model.maxVideosPerCall, 1);

      final result = await model.doGenerate(
        const VideoModelCallOptions(prompt: 'hello'),
      );
      expect(result.videos.single, isA<VideoModelVideoDataBytes>());
    });
  });
}

final class _FakeVideoModel implements VideoModel {
  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'fake.video';

  @override
  String get modelId => 'fake-video-model';

  @override
  FutureOr<int?> get maxVideosPerCall => 1;

  @override
  Future<VideoModelResult> doGenerate(VideoModelCallOptions options) async {
    return VideoModelResult(
      videos: [
        VideoModelVideoDataBytes(
          Uint8List.fromList([1, 2, 3]),
          mediaType: 'video/mp4',
        ),
      ],
      warnings: const [],
    );
  }
}
