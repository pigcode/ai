import 'dart:typed_data';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'registry_manifest.dart';
import 'store_digest.dart';
import 'store_format.dart';
import 'store_generation.dart';

final class EncodedStoreManifest {
  EncodedStoreManifest({
    required Uint8List bytes,
    required this.digest,
    required this.generation,
  }) : bytes = Uint8List.fromList(bytes);

  final Uint8List bytes;
  final String digest;
  final int generation;
}

final class StoreManifestCodec {
  const StoreManifestCodec();

  EncodedStoreManifest encode(Map<String, Object?> value) {
    final version = value['formatVersion'];
    final generation = value['generation'];
    if (version != agentManifestFormatVersion ||
        generation is! int ||
        generation <= 0) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Store manifest requires the current version and generation.',
      );
    }
    final bytes = canonicalJsonBytes(value);
    return EncodedStoreManifest(
      bytes: bytes,
      digest: storeHex(storeSha256(bytes)),
      generation: generation,
    );
  }

  Map<String, Object?> decodeGeneration(
    StoreGenerationFile generation,
    Uint8List bytes,
  ) {
    if (storeHex(storeSha256(bytes)) != generation.digest) {
      throw const StoreFormatException(
        StoreFormatErrorCode.digestMismatch,
        'Store manifest digest does not match its filename.',
      );
    }
    final object = decodeCanonicalRegistryObject(bytes);
    final version = object['formatVersion'];
    if (version != agentManifestFormatVersion) {
      throw const StoreFormatException(
        StoreFormatErrorCode.unsupportedVersion,
        'Unsupported Store manifest version.',
      );
    }
    if (object['generation'] != generation.generation) {
      throw const StoreFormatException(
        StoreFormatErrorCode.registryViolation,
        'Store manifest generation does not match its filename.',
      );
    }
    return object;
  }
}
