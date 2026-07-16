import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';

import '../internal/config.dart';
import '../internal/error.dart';
import '../internal/provider_options.dart';
import 'image_options.dart';

/// OpenAI Images(`/images/generations`)的 [ImageModel] 实现。
final class OpenAiImageModel implements ImageModel {
  OpenAiImageModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => imageModelSpecVersion;

  @override
  String get provider => '${config.providerName}.image';

  @override
  FutureOr<int?> get maxImagesPerCall => _modelMaxImagesPerCall[modelId] ?? 1;

  Uri get _generationsUrl => Uri.parse('${config.baseUrl}/images/generations');

  Uri get _editsUrl => Uri.parse('${config.baseUrl}/images/edits');

  @override
  Future<ImageModelResult> doGenerate(ImageModelCallOptions options) async {
    final openAiOptions = OpenAiImageProviderOptions.fromProviderOptions(
      resolveOpenAiProviderOptions(
        config.providerName,
        options.providerOptions,
      ),
    );
    final warnings = <Warning>[];

    if (options.aspectRatio != null) {
      warnings.add(
        UnsupportedWarning(
          'aspectRatio',
          details: 'This model does not support aspect ratio. '
              'Use `size` instead.',
        ),
      );
    }
    if (options.seed != null) {
      warnings.add(const UnsupportedWarning('seed'));
    }
    if (options.mask != null &&
        (options.files == null || options.files!.isEmpty)) {
      throw const InvalidArgumentError(
        argument: 'mask',
        message: 'mask requires at least one image file.',
      );
    }
    if (options.files != null && options.files!.isEmpty) {
      throw const InvalidArgumentError(
        argument: 'files',
        message: 'files must not be empty.',
      );
    }

    if (options.files != null) {
      return _doEdit(
        options: options,
        openAiOptions: openAiOptions,
        warnings: warnings,
      );
    }

    return _doGeneration(
      options: options,
      openAiOptions: openAiOptions,
      warnings: warnings,
    );
  }

  Future<ImageModelResult> _doGeneration({
    required ImageModelCallOptions options,
    required OpenAiImageProviderOptions openAiOptions,
    required List<Warning> warnings,
  }) async {
    final body = <String, Object?>{
      'model': modelId,
      'prompt': options.prompt,
      'n': options.n,
      'size': options.size,
      'quality': openAiOptions.quality,
      'style': openAiOptions.style,
      'background': openAiOptions.background,
      'moderation': openAiOptions.moderation,
      'output_format': openAiOptions.outputFormat,
      'output_compression': openAiOptions.outputCompression,
      'user': openAiOptions.user,
      if (!_hasDefaultResponseFormat(modelId)) 'response_format': 'b64_json',
    }..removeWhere((_, value) => value == null);

    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: _generationsUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    return _toImageModelResult(
      response: response,
      responseHeaders: responseHeaders,
      warnings: warnings,
      requestBody: jsonEncode(body),
    );
  }

  Future<ImageModelResult> _doEdit({
    required ImageModelCallOptions options,
    required OpenAiImageProviderOptions openAiOptions,
    required List<Warning> warnings,
  }) async {
    final files = options.files!;
    if (_shouldUseJsonEdit(files: files, mask: options.mask)) {
      return _doJsonEdit(
        options: options,
        openAiOptions: openAiOptions,
        warnings: warnings,
      );
    }

    Map<String, String>? responseHeaders;
    final response = await postMultipartToApi<JsonObject>(
      url: _editsUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      build: (request) {
        request.fields.addAll(
          _editFields(
            modelId: modelId,
            options: options,
            openAiOptions: openAiOptions,
          ),
        );
        for (var i = 0; i < files.length; i++) {
          request.files.add(
            _imageMultipartFile(
              files[i],
              field: files.length == 1 ? 'image' : 'image[]',
              filenamePrefix: files.length == 1 ? 'image' : 'image-${i + 1}',
              argument: 'files',
            ),
          );
        }
        final mask = options.mask;
        if (mask != null) {
          request.files.add(
            _imageMultipartFile(
              mask,
              field: 'mask',
              filenamePrefix: 'mask',
              argument: 'mask',
            ),
          );
        }
      },
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    return _toImageModelResult(
      response: response,
      responseHeaders: responseHeaders,
      warnings: warnings,
      requestBody: 'multipart/form-data',
    );
  }

  Future<ImageModelResult> _doJsonEdit({
    required ImageModelCallOptions options,
    required OpenAiImageProviderOptions openAiOptions,
    required List<Warning> warnings,
  }) async {
    final body = _editJsonBody(
      modelId: modelId,
      options: options,
      openAiOptions: openAiOptions,
    );

    Map<String, String>? responseHeaders;
    final response = await postJsonToApi<JsonObject>(
      url: _editsUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      body: body,
      successHandler: (ctx) async {
        responseHeaders = ctx.response.headers;
        return jsonResponseHandler<JsonObject>(
          decode: (json) => json! as JsonObject,
        )(ctx);
      },
      failureHandler: openAiFailedResponseHandler(),
      client: config.client,
      cancellation: options.cancellation,
    );

    return _toImageModelResult(
      response: response,
      responseHeaders: responseHeaders,
      warnings: warnings,
      requestBody: jsonEncode(body),
    );
  }

  ImageModelResult _toImageModelResult({
    required JsonObject response,
    required Map<String, String>? responseHeaders,
    required List<Warning> warnings,
    required String requestBody,
  }) {
    final data = response['data']! as List<Object?>;
    final images = data
        .map((item) =>
            base64Decode((item! as JsonObject)['b64_json']! as String))
        .map(Uint8List.fromList)
        .toList();
    final usage = response['usage'] as JsonObject?;
    final metadataKey = resolveOpenAiProviderOptionsName(config.providerName);

    return ImageModelResult(
      images: images,
      warnings: warnings,
      usage: usage == null
          ? const ImageModelUsage()
          : ImageModelUsage(
              inputTokens: (usage['input_tokens'] as num?)?.toInt(),
              outputTokens: (usage['output_tokens'] as num?)?.toInt(),
              totalTokens: (usage['total_tokens'] as num?)?.toInt(),
            ),
      providerMetadata: {
        metadataKey: {
          'images': _imageMetadata(
            response: response,
            data: data.cast<JsonObject>(),
          ),
        },
      },
      request: RequestInfo(body: requestBody),
      response: ResponseInfo(
        timestamp: DateTime.now(),
        modelId: modelId,
        headers: responseHeaders,
        body: response,
      ),
    );
  }
}

Map<String, String> _editFields({
  required String modelId,
  required ImageModelCallOptions options,
  required OpenAiImageProviderOptions openAiOptions,
}) {
  final fields = <String, String>{
    'model': modelId,
    'prompt': options.prompt,
    'n': options.n.toString(),
  };
  _addField(fields, 'size', options.size);
  _addField(fields, 'quality', openAiOptions.quality);
  _addField(fields, 'background', openAiOptions.background);
  _addField(fields, 'moderation', openAiOptions.moderation);
  _addField(fields, 'output_format', openAiOptions.outputFormat);
  _addField(
    fields,
    'output_compression',
    openAiOptions.outputCompression,
  );
  _addField(fields, 'input_fidelity', openAiOptions.inputFidelity);
  _addField(fields, 'user', openAiOptions.user);
  if (!_hasDefaultResponseFormat(modelId)) {
    fields['response_format'] = 'b64_json';
  }
  return fields;
}

JsonObject _editJsonBody({
  required String modelId,
  required ImageModelCallOptions options,
  required OpenAiImageProviderOptions openAiOptions,
}) {
  final body = <String, Object?>{
    'model': modelId,
    'prompt': options.prompt,
    'images': [
      for (final file in options.files!) _imageUrlReference(file),
    ],
    'mask': switch (options.mask) {
      final mask? => _imageUrlReference(mask),
      _ => null,
    },
    'n': options.n,
    'size': options.size,
    'quality': openAiOptions.quality,
    'background': openAiOptions.background,
    'moderation': openAiOptions.moderation,
    'output_format': openAiOptions.outputFormat,
    'output_compression': openAiOptions.outputCompression,
    'input_fidelity': openAiOptions.inputFidelity,
    'user': openAiOptions.user,
    if (!_hasDefaultResponseFormat(modelId)) 'response_format': 'b64_json',
  }..removeWhere((_, value) => value == null);
  return body;
}

void _addField(Map<String, String> fields, String key, Object? value) {
  if (value != null) {
    fields[key] = value.toString();
  }
}

JsonObject _imageUrlReference(ImageModelFile file) {
  return {
    'image_url': switch (file) {
      ImageModelFileBytes(:final bytes, :final mediaType) => _dataUrlFromBytes(
          bytes,
          mediaType ?? _imageMediaTypeFromBytes(bytes),
        ),
      ImageModelFileBase64(:final base64, :final mediaType) =>
        _dataUrlFromBase64(
          base64,
          mediaType ?? _imageMediaTypeFromBase64(base64),
        ),
      ImageModelFileUrl(:final url) => url.toString(),
    },
  };
}

String _dataUrlFromBytes(List<int> bytes, String mediaType) {
  return 'data:$mediaType;base64,${base64Encode(bytes)}';
}

String _dataUrlFromBase64(String base64, String mediaType) {
  base64Decode(base64);
  return 'data:$mediaType;base64,$base64';
}

bool _shouldUseJsonEdit({
  required List<ImageModelFile> files,
  required ImageModelFile? mask,
}) {
  return files.any((file) => file is ImageModelFileUrl) ||
      mask is ImageModelFileUrl;
}

http.MultipartFile _imageMultipartFile(
  ImageModelFile file, {
  required String field,
  required String filenamePrefix,
  required String argument,
}) {
  final resolved = _imageFileBytes(file, argument: argument);
  final mediaType = resolved.mediaType;
  return http.MultipartFile.fromBytes(
    field,
    resolved.bytes,
    filename: '$filenamePrefix.${mediaTypeToExtension(mediaType)}',
    contentType: MediaType.parse(mediaType),
  );
}

({List<int> bytes, String mediaType}) _imageFileBytes(
  ImageModelFile file, {
  required String argument,
}) {
  return switch (file) {
    ImageModelFileBytes(:final bytes, :final mediaType) => (
        bytes: bytes,
        mediaType: mediaType ?? _imageMediaTypeFromBytes(bytes),
      ),
    ImageModelFileBase64(:final base64, :final mediaType) => (
        bytes: base64Decode(base64),
        mediaType: mediaType ?? _imageMediaTypeFromBase64(base64),
      ),
    ImageModelFileUrl() => throw InvalidArgumentError(
        argument: argument,
        message: 'OpenAI image edits require byte or base64 image files.',
      ),
  };
}

String _imageMediaTypeFromBytes(List<int> bytes) {
  return detectMediaType(data: bytes, topLevelType: 'image') ?? 'image/png';
}

String _imageMediaTypeFromBase64(String base64) {
  return detectMediaType(data: base64, topLevelType: 'image') ?? 'image/png';
}

const _modelMaxImagesPerCall = <String, int>{
  'dall-e-3': 1,
  'dall-e-2': 10,
  'gpt-image-1': 10,
  'gpt-image-1-mini': 10,
  'gpt-image-1.5': 10,
  'gpt-image-2': 10,
  'chatgpt-image-latest': 10,
};

const _defaultResponseFormatPrefixes = <String>[
  'chatgpt-image-',
  'gpt-image-1-mini',
  'gpt-image-1.5',
  'gpt-image-1',
  'gpt-image-2',
];

bool _hasDefaultResponseFormat(String modelId) {
  return _defaultResponseFormatPrefixes.any(modelId.startsWith);
}

List<JsonObject> _imageMetadata({
  required JsonObject response,
  required List<JsonObject> data,
}) {
  return [
    for (var i = 0; i < data.length; i++)
      <String, Object?>{
        if (data[i]['revised_prompt'] != null)
          'revisedPrompt': data[i]['revised_prompt'],
        if (response['created'] != null) 'created': response['created'],
        if (response['size'] != null) 'size': response['size'],
        if (response['quality'] != null) 'quality': response['quality'],
        if (response['background'] != null)
          'background': response['background'],
        if (response['output_format'] != null)
          'outputFormat': response['output_format'],
        ..._distributeTokenDetails(
          response['usage'] is JsonObject
              ? (response['usage']! as JsonObject)['input_tokens_details']
                  as JsonObject?
              : null,
          i,
          data.length,
        ),
      },
  ];
}

JsonObject _distributeTokenDetails(
  JsonObject? details,
  int index,
  int total,
) {
  if (details == null) {
    return const {};
  }

  final result = <String, Object?>{};
  final imageTokens = (details['image_tokens'] as num?)?.toInt();
  if (imageTokens != null) {
    final base = imageTokens ~/ total;
    final remainder = imageTokens - base * (total - 1);
    result['imageTokens'] = index == total - 1 ? remainder : base;
  }

  final textTokens = (details['text_tokens'] as num?)?.toInt();
  if (textTokens != null) {
    final base = textTokens ~/ total;
    final remainder = textTokens - base * (total - 1);
    result['textTokens'] = index == total - 1 ? remainder : base;
  }

  return result;
}
