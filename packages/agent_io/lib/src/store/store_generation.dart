import 'dart:io';

final class StoreGenerationFile {
  const StoreGenerationFile({
    required this.file,
    required this.generation,
    required this.digest,
  });

  final File file;
  final int generation;
  final String digest;

  static StoreGenerationFile? tryParse(File file) {
    final name = file.uri.pathSegments.last;
    final match =
        RegExp(r'^([0-9]{20})-([a-f0-9]{64})\.json$').firstMatch(name);
    if (match == null) return null;
    final generation = int.tryParse(match.group(1)!);
    if (generation == null || generation <= 0) return null;
    return StoreGenerationFile(
      file: file,
      generation: generation,
      digest: match.group(2)!,
    );
  }
}
