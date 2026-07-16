import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('detectMediaType', () {
    test('detects image, audio, and application signatures from bytes', () {
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x00]),
        ),
        'image/png',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x00]),
        ),
        'application/pdf',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(
            <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x41, 0x56, 0x45],
          ),
          topLevelType: 'audio',
        ),
        'audio/wav',
      );
    });

    test('detects signatures from base64 strings', () {
      final webpBytes = Uint8List.fromList(
        <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x45, 0x42, 0x50],
      );

      expect(
        detectMediaType(data: base64Encode(webpBytes)),
        'image/webp',
      );
    });

    test('filters by top-level media type', () {
      final wavBytes = Uint8List.fromList(
        <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x41, 0x56, 0x45],
      );

      expect(
        detectMediaType(data: wavBytes, topLevelType: 'image'),
        isNull,
      );
      expect(
        detectMediaType(data: wavBytes, topLevelType: 'audio'),
        'audio/wav',
      );
    });

    test('skips ID3 tags before detecting MP3 payloads', () {
      final id3ThenMp3 = Uint8List.fromList(
        <int>[0x49, 0x44, 0x33, 0, 0, 0, 0, 0, 0, 0, 0xff, 0xfb],
      );

      expect(
        detectMediaType(data: id3ThenMp3, topLevelType: 'audio'),
        'audio/mpeg',
      );
    });

    test('detects MP4 audio after its box-size header', () {
      final m4aBytes = Uint8List.fromList(
        <int>[0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70],
      );

      expect(
        detectMediaType(data: m4aBytes, topLevelType: 'audio'),
        'audio/mp4',
      );
    });

    test('prefers QuickTime over generic MP4 when top-level type is video', () {
      final movBytes = Uint8List.fromList(
        <int>[0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74],
      );

      expect(
        detectMediaType(data: movBytes, topLevelType: 'video'),
        'video/quicktime',
      );
    });

    test('does not guess ambiguous MP4 boxes without a top-level type', () {
      final mp4Bytes = Uint8List.fromList(
        <int>[0x00, 0x00, 0x00, 0x20, 0x66, 0x74, 0x79, 0x70],
      );

      expect(detectMediaType(data: mp4Bytes), isNull);
    });

    test('does not guess ambiguous WebM containers without a top-level type',
        () {
      final webmBytes = Uint8List.fromList(<int>[0x1a, 0x45, 0xdf, 0xa3]);

      expect(detectMediaType(data: webmBytes), isNull);
      expect(
        detectMediaType(data: webmBytes, topLevelType: 'audio'),
        'audio/webm',
      );
      expect(
        detectMediaType(data: webmBytes, topLevelType: 'video'),
        'video/webm',
      );
    });

    test('does not guess ambiguous Ogg containers without a top-level type',
        () {
      final oggBytes = Uint8List.fromList(<int>[0x4f, 0x67, 0x67, 0x53]);

      expect(detectMediaType(data: oggBytes), isNull);
      expect(
        detectMediaType(data: oggBytes, topLevelType: 'audio'),
        'audio/ogg',
      );
      expect(
        detectMediaType(data: oggBytes, topLevelType: 'video'),
        'video/ogg',
      );
    });

    test('detects common AAC stream headers', () {
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0xff, 0xf1, 0x50, 0x80]),
          topLevelType: 'audio',
        ),
        'audio/aac',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0xff, 0xf9, 0x50, 0x80]),
          topLevelType: 'audio',
        ),
        'audio/aac',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0x41, 0x44, 0x49, 0x46]),
          topLevelType: 'audio',
        ),
        'audio/aac',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(<int>[0x40, 0x15, 0x00, 0x00]),
          topLevelType: 'audio',
        ),
        isNull,
      );
    });

    test('requires the AVI RIFF form tag for x-msvideo', () {
      final wavBytes = Uint8List.fromList(
        <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x57, 0x41, 0x56, 0x45],
      );
      final aviBytes = Uint8List.fromList(
        <int>[0x52, 0x49, 0x46, 0x46, 1, 2, 3, 4, 0x41, 0x56, 0x49, 0x20],
      );

      expect(detectMediaType(data: wavBytes, topLevelType: 'video'), isNull);
      expect(
        detectMediaType(data: aviBytes, topLevelType: 'video'),
        'video/x-msvideo',
      );
    });

    test('detects AVIF and HEIC with variable ftyp box sizes', () {
      expect(
        detectMediaType(
          data: Uint8List.fromList(
            <int>[
              0x00,
              0x00,
              0x00,
              0x18,
              0x66,
              0x74,
              0x79,
              0x70,
              0x61,
              0x76,
              0x69,
              0x66,
            ],
          ),
          topLevelType: 'image',
        ),
        'image/avif',
      );
      expect(
        detectMediaType(
          data: Uint8List.fromList(
            <int>[
              0x00,
              0x00,
              0x00,
              0x1c,
              0x66,
              0x74,
              0x79,
              0x70,
              0x68,
              0x65,
              0x69,
              0x63,
            ],
          ),
          topLevelType: 'image',
        ),
        'image/heic',
      );
    });
  });

  group('media type string helpers', () {
    test('returns the top-level segment', () {
      expect(getTopLevelMediaType('image/png'), 'image');
      expect(getTopLevelMediaType('image/*'), 'image');
      expect(getTopLevelMediaType('image'), 'image');
      expect(getTopLevelMediaType('/'), '');
    });

    test('recognizes full media types only when subtype is concrete', () {
      expect(isFullMediaType('image/png'), isTrue);
      expect(isFullMediaType('image/*'), isFalse);
      expect(isFullMediaType('image/'), isFalse);
      expect(isFullMediaType('image'), isFalse);
    });

    test('maps common media types to file extensions', () {
      expect(mediaTypeToExtension('audio/mpeg'), 'mp3');
      expect(mediaTypeToExtension('audio/x-wav'), 'wav');
      expect(mediaTypeToExtension('audio/opus'), 'ogg');
      expect(mediaTypeToExtension('audio/mp4'), 'm4a');
      expect(mediaTypeToExtension('video/mp4'), 'mp4');
      expect(mediaTypeToExtension('IMAGE/PNG'), 'png');
    });

    test('strips media type parameters before deriving file extensions', () {
      expect(mediaTypeToExtension('text/plain; charset=utf-8'), 'plain');
      expect(mediaTypeToExtension('audio/mpeg; codecs=mp3'), 'mp3');
      expect(mediaTypeToExtension('IMAGE/PNG; foo=bar'), 'png');
    });

    test('strips all extension segments after the first dot', () {
      expect(stripFileExtension('report.pdf'), 'report');
      expect(stripFileExtension('archive.tar.gz'), 'archive');
      expect(stripFileExtension('filename'), 'filename');
    });
  });

  group('resolveFullMediaType', () {
    test('returns already-full media types', () {
      final part = FilePart(
        data: FileDataBytes(Uint8List.fromList(<int>[1])),
        mediaType: 'image/png',
      );

      expect(resolveFullMediaType(part), 'image/png');
    });

    test('detects inline byte subtypes for top-level media types', () {
      final part = FilePart(
        data: FileDataBytes(
          Uint8List.fromList(<int>[0x89, 0x50, 0x4e, 0x47, 0x00]),
        ),
        mediaType: 'image',
      );

      expect(resolveFullMediaType(part), 'image/png');
    });

    test('rejects unresolved inline media types', () {
      final part = FilePart(
        data: FileDataBytes(Uint8List.fromList(<int>[0x01, 0x02])),
        mediaType: 'image',
      );

      expect(
        () => resolveFullMediaType(part),
        throwsA(isA<UnsupportedFunctionalityError>().having(
          (error) => error.functionality,
          'functionality',
          contains('could not be auto-detected'),
        )),
      );
    });

    test('rejects non-inline top-level media types', () {
      final part = FilePart(
        data: FileDataUrl(Uri.parse('https://example.com/image')),
        mediaType: 'image',
      );

      expect(
        () => resolveFullMediaType(part),
        throwsA(isA<UnsupportedFunctionalityError>().having(
          (error) => error.functionality,
          'functionality',
          contains('not passed as inline bytes'),
        )),
      );
    });
  });
}
