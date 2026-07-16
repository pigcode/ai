import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// Detects a file's IANA media type from raw bytes or a base64 string.
///
/// When [topLevelType] is provided, only signatures for that top-level segment
/// are considered.
String? detectMediaType({
  required Object data,
  String? topLevelType,
}) {
  final bytes = _mediaBytes(data);
  if (bytes == null) {
    return null;
  }

  final signatures = topLevelType == null
      ? <_MediaTypeSignature>[
          ..._imageMediaTypeSignatures,
          ..._documentMediaTypeSignatures,
          ..._audioMediaTypeSignatures.where(_isUnambiguousSignature),
          ..._videoMediaTypeSignatures.where(_isUnambiguousSignature),
        ]
      : _topLevelSignatureTables[topLevelType];

  if (signatures == null) {
    return null;
  }

  final processedBytes = _stripId3TagsIfPresent(bytes);
  for (final signature in signatures) {
    if (_hasSignature(processedBytes, signature.bytesPrefix)) {
      return signature.mediaType;
    }
  }
  return null;
}

/// Returns the top-level segment of a media type, i.e. the part before `/`.
String getTopLevelMediaType(String mediaType) {
  final slashIndex = mediaType.indexOf('/');
  return slashIndex == -1 ? mediaType : mediaType.substring(0, slashIndex);
}

/// Returns whether [mediaType] has a concrete non-wildcard subtype.
bool isFullMediaType(String mediaType) {
  final slashIndex = mediaType.indexOf('/');
  if (slashIndex == -1) {
    return false;
  }
  final subtype = mediaType.substring(slashIndex + 1);
  return subtype.isNotEmpty && subtype != '*';
}

/// Maps a media type to a common file extension.
String mediaTypeToExtension(String mediaType) {
  final normalizedType = mediaType.toLowerCase().split(';').first.trim();
  final parts = normalizedType.split('/');
  final topLevelType = parts.first;
  final subtype = parts.length > 1 ? parts[1] : '';
  return switch (subtype) {
    'mpeg' => 'mp3',
    'x-wav' => 'wav',
    'opus' => 'ogg',
    'mp4' when topLevelType == 'audio' => 'm4a',
    'x-m4a' => 'm4a',
    _ => subtype,
  };
}

/// Strips file extension segments from a filename.
String stripFileExtension(String filename) {
  final firstDotIndex = filename.indexOf('.');
  return firstDotIndex == -1 ? filename : filename.substring(0, firstDotIndex);
}

/// Resolves a [provider.FilePart] media type to full `type/subtype` form.
///
/// Top-level-only media types are detected from inline byte/base64 data.
String resolveFullMediaType(provider.FilePart part) {
  if (isFullMediaType(part.mediaType)) {
    return part.mediaType;
  }

  final Object data;
  switch (part.data) {
    case provider.FileDataBytes(:final bytes):
      data = bytes;
    case provider.FileDataBase64(:final base64):
      data = base64;
    case provider.FileDataText() ||
          provider.FileDataUrl() ||
          provider.FileDataReference():
      throw provider.UnsupportedFunctionalityError(
        functionality: 'file of media type "${part.mediaType}" must specify '
            'subtype since it is not passed as inline bytes',
      );
  }

  final detected = detectMediaType(
    data: data,
    topLevelType: getTopLevelMediaType(part.mediaType),
  );
  if (detected != null) {
    return detected;
  }

  throw provider.UnsupportedFunctionalityError(
    functionality: 'file of media type "${part.mediaType}" must specify '
        'subtype since it could not be auto-detected',
  );
}

Uint8List? _mediaBytes(Object data) {
  if (data is Uint8List) {
    return data;
  }
  if (data is List<int>) {
    return Uint8List.fromList(data);
  }
  if (data is String) {
    try {
      return base64Decode(data);
    } on FormatException {
      return null;
    }
  }
  return null;
}

Uint8List _stripId3TagsIfPresent(Uint8List bytes) {
  if (bytes.length <= 10 ||
      bytes[0] != 0x49 ||
      bytes[1] != 0x44 ||
      bytes[2] != 0x33) {
    return bytes;
  }

  final id3Size = ((bytes[6] & 0x7f) << 21) |
      ((bytes[7] & 0x7f) << 14) |
      ((bytes[8] & 0x7f) << 7) |
      (bytes[9] & 0x7f);
  final payloadStart = id3Size + 10;
  if (payloadStart >= bytes.length) {
    return Uint8List(0);
  }
  return Uint8List.sublistView(bytes, payloadStart);
}

bool _hasSignature(Uint8List bytes, List<int?> prefix) {
  if (bytes.length < prefix.length) {
    return false;
  }
  for (var index = 0; index < prefix.length; index++) {
    final byte = prefix[index];
    if (byte != null && bytes[index] != byte) {
      return false;
    }
  }
  return true;
}

bool _isUnambiguousSignature(_MediaTypeSignature signature) {
  return signature.mediaType != 'audio/mp4' &&
      signature.mediaType != 'video/mp4' &&
      signature.mediaType != 'audio/webm' &&
      signature.mediaType != 'video/webm' &&
      signature.mediaType != 'audio/ogg' &&
      signature.mediaType != 'video/ogg';
}

final class _MediaTypeSignature {
  const _MediaTypeSignature(this.mediaType, this.bytesPrefix);

  final String mediaType;
  final List<int?> bytesPrefix;
}

const _imageMediaTypeSignatures = <_MediaTypeSignature>[
  _MediaTypeSignature('image/gif', <int?>[0x47, 0x49, 0x46]),
  _MediaTypeSignature('image/png', <int?>[0x89, 0x50, 0x4e, 0x47]),
  _MediaTypeSignature('image/jpeg', <int?>[0xff, 0xd8]),
  _MediaTypeSignature(
    'image/webp',
    <int?>[
      0x52,
      0x49,
      0x46,
      0x46,
      null,
      null,
      null,
      null,
      0x57,
      0x45,
      0x42,
      0x50
    ],
  ),
  _MediaTypeSignature('image/bmp', <int?>[0x42, 0x4d]),
  _MediaTypeSignature('image/tiff', <int?>[0x49, 0x49, 0x2a, 0x00]),
  _MediaTypeSignature('image/tiff', <int?>[0x4d, 0x4d, 0x00, 0x2a]),
  _MediaTypeSignature(
    'image/avif',
    <int?>[
      null,
      null,
      null,
      null,
      0x66,
      0x74,
      0x79,
      0x70,
      0x61,
      0x76,
      0x69,
      0x66
    ],
  ),
  _MediaTypeSignature(
    'image/heic',
    <int?>[
      null,
      null,
      null,
      null,
      0x66,
      0x74,
      0x79,
      0x70,
      0x68,
      0x65,
      0x69,
      0x63
    ],
  ),
];

const _documentMediaTypeSignatures = <_MediaTypeSignature>[
  _MediaTypeSignature('application/pdf', <int?>[0x25, 0x50, 0x44, 0x46]),
];

const _audioMediaTypeSignatures = <_MediaTypeSignature>[
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xfb]),
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xfa]),
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xf3]),
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xf2]),
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xe3]),
  _MediaTypeSignature('audio/mpeg', <int?>[0xff, 0xe2]),
  _MediaTypeSignature(
    'audio/wav',
    <int?>[
      0x52,
      0x49,
      0x46,
      0x46,
      null,
      null,
      null,
      null,
      0x57,
      0x41,
      0x56,
      0x45
    ],
  ),
  _MediaTypeSignature('audio/ogg', <int?>[0x4f, 0x67, 0x67, 0x53]),
  _MediaTypeSignature('audio/flac', <int?>[0x66, 0x4c, 0x61, 0x43]),
  _MediaTypeSignature('audio/aac', <int?>[0xff, 0xf1]),
  _MediaTypeSignature('audio/aac', <int?>[0xff, 0xf9]),
  _MediaTypeSignature('audio/aac', <int?>[0x41, 0x44, 0x49, 0x46]),
  _MediaTypeSignature(
    'audio/mp4',
    <int?>[0x00, 0x00, 0x00, null, 0x66, 0x74, 0x79, 0x70],
  ),
  _MediaTypeSignature('audio/webm', <int?>[0x1a, 0x45, 0xdf, 0xa3]),
];

const _videoMediaTypeSignatures = <_MediaTypeSignature>[
  _MediaTypeSignature(
    'video/quicktime',
    <int?>[0x00, 0x00, 0x00, 0x14, 0x66, 0x74, 0x79, 0x70, 0x71, 0x74],
  ),
  _MediaTypeSignature(
    'video/mp4',
    <int?>[0x00, 0x00, 0x00, null, 0x66, 0x74, 0x79, 0x70],
  ),
  _MediaTypeSignature('video/webm', <int?>[0x1a, 0x45, 0xdf, 0xa3]),
  _MediaTypeSignature('video/ogg', <int?>[0x4f, 0x67, 0x67, 0x53]),
  _MediaTypeSignature(
    'video/x-msvideo',
    <int?>[
      0x52,
      0x49,
      0x46,
      0x46,
      null,
      null,
      null,
      null,
      0x41,
      0x56,
      0x49,
      0x20
    ],
  ),
];

const _topLevelSignatureTables = <String, List<_MediaTypeSignature>>{
  'image': _imageMediaTypeSignatures,
  'audio': _audioMediaTypeSignatures,
  'video': _videoMediaTypeSignatures,
  'application': _documentMediaTypeSignatures,
};
