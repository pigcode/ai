import 'dart:typed_data';

import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as contracts;
import 'package:test/test.dart';

import '../support/logging.dart';

void main() {
  group('uploadFile', () {
    test('passes file data and options through to Files.uploadFile', () async {
      final records = captureWarningLogs();
      final files = _RecordingFiles(
        result: const contracts.FilesUploadResult(
          providerReference: {'mock': 'file-1'},
          mediaType: 'text/plain',
          filename: 'note.txt',
          warnings: [contracts.OtherWarning('file note')],
        ),
      );

      final result = await uploadFile(
        api: files,
        data: const contracts.FileDataText('hello'),
        filename: 'note.txt',
        providerOptions: const {
          'mock': {'purpose': 'assistants'},
        },
      );

      expect(files.calls, hasLength(1));
      expect(files.calls.single.data, const contracts.FileDataText('hello'));
      expect(files.calls.single.mediaType, 'text/plain');
      expect(files.calls.single.filename, 'note.txt');
      expect(files.calls.single.providerOptions, {
        'mock': {'purpose': 'assistants'},
      });
      expect(result.providerReference, {'mock': 'file-1'});
      expect(result.mediaType, 'text/plain');
      expect(result.filename, 'note.txt');
      expect(result.warnings, [const contracts.OtherWarning('file note')]);
      expect(records.map((record) => record.message), [
        'Pigcode AI Warning (mock.files): file note',
      ]);
    });

    test('detects common binary media types when mediaType is omitted',
        () async {
      final files = _RecordingFiles(
        result: const contracts.FilesUploadResult(
          providerReference: {'mock': 'file-1'},
          warnings: [],
        ),
      );

      await uploadFile(
        api: files,
        data: contracts.FileDataBytes(
          Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46]),
        ),
      );

      expect(files.calls.single.mediaType, 'application/pdf');
    });

    test('resolves Files from Provider.files()', () async {
      final files = _RecordingFiles(
        result: const contracts.FilesUploadResult(
          providerReference: {'mock': 'file-1'},
          warnings: [],
        ),
      );
      final provider = _ProviderWithResources(files: files);

      await uploadFile(
        api: provider,
        data: const contracts.FileDataText('hello'),
      );

      expect(provider.filesCalls, 1);
      expect(files.calls, hasLength(1));
    });
  });
}

final class _RecordingFiles implements contracts.Files {
  _RecordingFiles({required this.result});

  final contracts.FilesUploadResult result;
  final List<contracts.FilesUploadOptions> calls = [];

  @override
  String get specificationVersion => 'v4';

  @override
  String get provider => 'mock.files';

  @override
  Future<contracts.FilesUploadResult> uploadFile(
    contracts.FilesUploadOptions options,
  ) async {
    calls.add(options);
    return result;
  }
}

final class _ProviderWithResources implements contracts.Provider {
  _ProviderWithResources({required contracts.Files files}) : _files = files;

  final contracts.Files _files;
  var filesCalls = 0;

  @override
  String get specificationVersion => 'v4';

  @override
  contracts.LanguageModel languageModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.EmbeddingModel embeddingModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.ImageModel imageModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.TranscriptionModel transcriptionModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.SpeechModel speechModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.VideoModel videoModel(String modelId) {
    throw UnimplementedError();
  }

  @override
  contracts.RerankingModel rerankingModel(String modelId) {
    throw const contracts.UnsupportedFunctionalityError(
      functionality: 'rerankingModel',
    );
  }

  @override
  contracts.Files files() {
    filesCalls += 1;
    return _files;
  }

  @override
  contracts.Skills skills() {
    throw const contracts.UnsupportedFunctionalityError(
      functionality: 'skills',
    );
  }
}
