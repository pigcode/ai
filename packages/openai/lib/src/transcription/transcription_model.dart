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
import 'transcription_options.dart';

/// OpenAI Audio Transcriptions(`/audio/transcriptions`)的 [TranscriptionModel] 实现。
final class OpenAiTranscriptionModel implements StreamableTranscriptionModel {
  OpenAiTranscriptionModel(this.modelId, {required this.config});

  @override
  final String modelId;

  /// 共享的 provider 配置(baseUrl/headers/client)。
  final OpenAiConfig config;

  @override
  String get specificationVersion => transcriptionModelSpecVersion;

  @override
  String get provider => '${config.providerName}.transcription';

  Uri get _requestUrl => Uri.parse('${config.baseUrl}/audio/transcriptions');

  @override
  Future<TranscriptionModelResult> doGenerate(
    TranscriptionModelCallOptions options,
  ) async {
    if (_isRealtimeTranscriptionModelId(modelId)) {
      throw UnsupportedFunctionalityError(
        functionality: 'non-streaming transcription with $modelId',
      );
    }

    final resolvedProviderOptions = resolveOpenAiProviderOptions(
      config.providerName,
      options.providerOptions,
    );
    final hasOpenAiOptions = resolvedProviderOptions?['openai'] != null;
    final openAiOptions =
        OpenAiTranscriptionProviderOptions.fromProviderOptions(
      resolvedProviderOptions,
    );
    final timestampGranularities = openAiOptions.timestampGranularities;
    if (_isGpt4oTranscribeModel(modelId) &&
        timestampGranularities != null &&
        timestampGranularities.isNotEmpty) {
      throw UnsupportedFunctionalityError(
        functionality: 'timestamp granularities with $modelId',
      );
    }

    final fields = <String, String>{'model': modelId};
    if (modelId == 'whisper-1') {
      fields['response_format'] = 'verbose_json';
    } else if (hasOpenAiOptions) {
      fields['response_format'] =
          _isGpt4oTranscribeModel(modelId) ? 'json' : 'verbose_json';
    }
    _addField(fields, 'language', openAiOptions.language);
    _addField(fields, 'prompt', openAiOptions.prompt);
    _addField(fields, 'temperature', openAiOptions.temperature);

    final extraParts = <http.MultipartFile>[
      for (final item in openAiOptions.include ?? const <String>[])
        http.MultipartFile.fromString('include[]', item),
      for (final item in timestampGranularities ?? const <String>[])
        http.MultipartFile.fromString('timestamp_granularities[]', item),
    ];

    final audioBytes = _audioBytes(options.audio);
    final file = http.MultipartFile.fromBytes(
      'file',
      audioBytes,
      filename: 'audio.${_mediaTypeExtension(options.mediaType)}',
      contentType: MediaType.parse(options.mediaType),
    );

    Map<String, String>? responseHeaders;
    final response = await _postMultipartToApi<JsonObject>(
      url: _requestUrl,
      headers: combineHeaders([config.headers(), options.headers]),
      fields: fields,
      files: [file, ...extraParts],
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

    return TranscriptionModelResult(
      text: _string(response, 'text'),
      segments: _segments(response),
      language: _languageCode(response['language'] as String?),
      durationInSeconds: (response['duration'] as num?)?.toDouble(),
      warnings: const <Warning>[],
      response: ResponseInfo(
        timestamp: DateTime.now(),
        modelId: modelId,
        headers: responseHeaders,
        body: response,
      ),
    );
  }

  @override
  Future<TranscriptionModelStreamResult> doStream(
    TranscriptionModelStreamOptions options,
  ) async {
    if (!_isRealtimeTranscriptionModelId(modelId)) {
      throw UnsupportedFunctionalityError(
        functionality: 'streaming transcription with $modelId',
      );
    }

    final resolvedProviderOptions = resolveOpenAiProviderOptions(
      config.providerName,
      options.providerOptions,
    );
    final openAiOptions =
        OpenAiTranscriptionProviderOptions.fromProviderOptions(
      resolvedProviderOptions,
    );
    final warnings = _streamingWarnings(resolvedProviderOptions);
    final sessionUpdate = _buildRealtimeTranscriptionSession(
      modelId: modelId,
      inputAudioFormat: options.inputAudioFormat,
      providerOptions: openAiOptions,
    );
    final headers = combineHeaders([config.headers(), options.headers]);
    final connection = config.webSocketConnector(
      _realtimeTranscriptionUrl(config.baseUrl),
      protocols: _realtimeProtocols(headers),
      headers: headers,
    );

    return TranscriptionModelStreamResult(
      request: RequestInfo(body: sessionUpdate),
      response: ResponseInfo(
        timestamp: DateTime.now(),
        modelId: modelId,
      ),
      stream: _createRealtimeTranscriptionStream(
        connection: connection,
        sessionUpdate: sessionUpdate,
        language: openAiOptions.language,
        warnings: warnings,
        audio: options.audio,
        cancellation: options.cancellation,
        includeRawChunks: options.includeRawChunks,
      ),
    );
  }
}

List<Warning> _streamingWarnings(ProviderOptions? providerOptions) {
  final rawOpenAiOptions = providerOptions?['openai'];
  if (rawOpenAiOptions == null) {
    return const <Warning>[];
  }

  final warnings = <Warning>[];
  for (final option in const <String>[
    'include',
    'prompt',
    'temperature',
    'timestampGranularities',
  ]) {
    if (rawOpenAiOptions[option] != null) {
      warnings.add(
        UnsupportedWarning(
          'providerOptions.openai.$option',
          details: 'OpenAI streaming transcription does not support $option.',
        ),
      );
    }
  }
  return warnings;
}

Uri _realtimeTranscriptionUrl(String baseUrl) {
  final uri = Uri.parse('$baseUrl/realtime?intent=transcription');
  return uri.replace(scheme: uri.scheme == 'http' ? 'ws' : 'wss');
}

List<String> _realtimeProtocols(Map<String, String> headers) {
  final authorization = _headerValue(headers, 'authorization');
  final token = authorization != null && authorization.startsWith('Bearer ')
      ? authorization.substring('Bearer '.length)
      : null;
  final organization = _headerValue(headers, 'openai-organization');
  final project = _headerValue(headers, 'openai-project');
  return [
    'realtime',
    if (token != null) 'openai-insecure-api-key.$token',
    if (organization != null) 'openai-organization.$organization',
    if (project != null) 'openai-project.$project',
  ];
}

String? _headerValue(Map<String, String> headers, String name) {
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == name) {
      return entry.value;
    }
  }
  return null;
}

JsonObject _buildRealtimeTranscriptionSession({
  required String modelId,
  required TranscriptionInputAudioFormat inputAudioFormat,
  required OpenAiTranscriptionProviderOptions providerOptions,
}) {
  return <String, Object?>{
    'type': 'session.update',
    'session': <String, Object?>{
      'type': 'transcription',
      'audio': <String, Object?>{
        'input': <String, Object?>{
          'format': <String, Object?>{
            'type': inputAudioFormat.type,
            if (inputAudioFormat.rate != null) 'rate': inputAudioFormat.rate,
          },
          'transcription': <String, Object?>{
            'model': modelId,
            if (providerOptions.language != null)
              'language': providerOptions.language,
            if (providerOptions.streaming?.delay != null)
              'delay': providerOptions.streaming!.delay,
          },
          'turn_detection': null,
        },
      },
      if (providerOptions.streaming?.include != null)
        'include': providerOptions.streaming!.include,
    },
  };
}

Stream<TranscriptionModelStreamPart> _createRealtimeTranscriptionStream({
  required OpenAiWebSocketConnection connection,
  required JsonObject sessionUpdate,
  required String? language,
  required List<Warning> warnings,
  required Stream<TranscriptionAudio> audio,
  required CancellationSignal? cancellation,
  required bool? includeRawChunks,
}) {
  final controller = StreamController<TranscriptionModelStreamPart>();
  StreamSubscription<TranscriptionAudio>? audioSubscription;
  Completer<void>? audioDone;
  var finished = false;

  Future<void> closeConnection([int? closeCode]) async {
    try {
      await connection.close(closeCode);
    } catch (_) {
      // Closing is best effort; the stream surface already carries the result.
    }
  }

  Future<void> cleanup([int? closeCode]) async {
    final subscription = audioSubscription;
    if (subscription != null) {
      try {
        await subscription.cancel();
      } catch (_) {
        // Audio cleanup is best effort; terminal state is already emitted.
      }
    }
    final done = audioDone;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
    await closeConnection(closeCode);
  }

  Future<void> finish(String text, String? id) async {
    if (finished) {
      return;
    }
    finished = true;
    if (id != null) {
      controller.add(TranscriptionFinal(id: id, text: text));
    }
    controller.add(TranscriptionFinish(
      text: text,
      segments: const <TranscriptionSegment>[],
      language: language,
    ));
    unawaited(cleanup(1000));
    await controller.close();
  }

  Future<void> finishWithError(Object error) async {
    if (finished) {
      return;
    }
    finished = true;
    controller.add(TranscriptionStreamError(error));
    unawaited(cleanup());
    await controller.close();
  }

  Future<void> sendAudio() async {
    final done = Completer<void>();
    audioDone = done;
    audioSubscription = audio.listen(
      (chunk) {
        if (finished) {
          return;
        }
        connection.add(jsonEncode(<String, Object?>{
          'type': 'input_audio_buffer.append',
          'audio': _audioBase64(chunk),
        }));
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!done.isCompleted) {
          done.completeError(error, stackTrace);
        }
      },
      onDone: () {
        if (!finished) {
          connection.add(jsonEncode(<String, Object?>{
            'type': 'input_audio_buffer.commit',
          }));
        }
        if (!done.isCompleted) {
          done.complete();
        }
      },
      cancelOnError: true,
    );
    await done.future;
  }

  Object cancellationError() =>
      StateError('OpenAI realtime transcription cancelled');

  void handleCancellation() {
    if (!finished) {
      unawaited(finishWithError(cancellationError()));
    }
  }

  Future<void> run() async {
    try {
      if (cancellation?.isCancelled ?? false) {
        await finishWithError(cancellationError());
        return;
      }
      final whenCancelled = cancellation?.whenCancelled;
      if (whenCancelled != null) {
        unawaited(whenCancelled.then((_) {
          handleCancellation();
        }));
      }

      await connection.ready;
      if (finished) {
        return;
      }
      controller.add(TranscriptionStreamStart(warnings));
      connection.add(jsonEncode(sessionUpdate));
      unawaited(sendAudio().catchError(finishWithError));

      await for (final message in connection.stream) {
        if (finished) {
          break;
        }
        final raw = _decodeWebSocketJson(message);
        if (raw == null) {
          continue;
        }
        if (includeRawChunks ?? false) {
          controller.add(TranscriptionRaw(raw));
        }

        switch (raw['type']) {
          case 'conversation.item.input_audio_transcription.delta':
            controller.add(TranscriptionDelta(
              id: raw['item_id'] as String?,
              delta: raw['delta'] as String? ?? '',
            ));
          case 'conversation.item.input_audio_transcription.completed':
            await finish(
              raw['transcript'] as String? ?? '',
              raw['item_id'] as String?,
            );
          case 'error':
            final error = raw['error'];
            final message = error is JsonObject
                ? error['message'] as String?
                : 'OpenAI realtime error';
            await finishWithError(
                Exception(message ?? 'OpenAI realtime error'));
          case 'conversation.item.input_audio_transcription.failed':
            final error = raw['error'];
            final message = error is JsonObject
                ? error['message'] as String?
                : 'OpenAI realtime transcription failed';
            await finishWithError(
                Exception(message ?? 'OpenAI realtime transcription failed'));
        }
      }

      if (!finished) {
        finished = true;
        await cleanup();
        await controller.close();
      }
    } catch (error) {
      await finishWithError(error);
    }
  }

  controller.onCancel = () async {
    if (finished) {
      return;
    }
    finished = true;
    await cleanup();
  };

  unawaited(run());
  return controller.stream;
}

JsonObject? _decodeWebSocketJson(Object? message) {
  final text = switch (message) {
    String value => value,
    List<int> bytes => utf8.decode(bytes),
    _ => null,
  };
  if (text == null) {
    return null;
  }
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, Object?>) {
      return decoded;
    }
  } catch (_) {
    return null;
  }
  return null;
}

String _audioBase64(TranscriptionAudio audio) {
  return switch (audio) {
    TranscriptionAudioBytes(:final bytes) => base64Encode(bytes),
    TranscriptionAudioBase64(:final base64) => base64,
  };
}

bool _isRealtimeTranscriptionModelId(String modelId) =>
    modelId == 'gpt-realtime-whisper' ||
    modelId.startsWith('gpt-realtime-whisper-');

bool _isGpt4oTranscribeModel(String modelId) =>
    modelId.startsWith('gpt-4o-transcribe') ||
    modelId.startsWith('gpt-4o-mini-transcribe');

void _addField(Map<String, String> fields, String key, Object? value) {
  if (value != null) {
    fields[key] = value.toString();
  }
}

Uint8List _audioBytes(TranscriptionAudio audio) {
  return switch (audio) {
    TranscriptionAudioBytes(:final bytes) => bytes,
    TranscriptionAudioBase64(:final base64) => base64Decode(base64),
  };
}

String _mediaTypeExtension(String mediaType) {
  final normalized = mediaType.split(';').first.trim().toLowerCase();
  return switch (normalized) {
    'audio/mpeg' || 'audio/mp3' => 'mp3',
    'audio/wav' || 'audio/x-wav' || 'audio/wave' => 'wav',
    'audio/mp4' => 'mp4',
    'audio/webm' => 'webm',
    'audio/ogg' => 'ogg',
    'audio/flac' => 'flac',
    'audio/m4a' || 'audio/x-m4a' => 'm4a',
    _ => normalized.contains('/')
        ? normalized.split('/').last.replaceAll(RegExp(r'[^a-z0-9.+-]'), '')
        : 'bin',
  };
}

String _string(JsonObject object, String key) {
  final value = object[key];
  if (value is String) {
    return value;
  }
  throw TypeValidationError(
    value: object,
    message: 'Expected "$key" to be a string.',
  );
}

List<TranscriptionSegment> _segments(JsonObject response) {
  final segments = response['segments'];
  if (segments is List<Object?>) {
    return [
      for (final item in segments)
        TranscriptionSegment(
          text: _string(item! as JsonObject, 'text'),
          startSecond: ((item as JsonObject)['start']! as num).toDouble(),
          endSecond: (item['end']! as num).toDouble(),
        ),
    ];
  }

  final words = response['words'];
  if (words is List<Object?>) {
    return [
      for (final item in words)
        TranscriptionSegment(
          text: _string(item! as JsonObject, 'word'),
          startSecond: ((item as JsonObject)['start']! as num).toDouble(),
          endSecond: (item['end']! as num).toDouble(),
        ),
    ];
  }

  return const <TranscriptionSegment>[];
}

String? _languageCode(String? language) {
  if (language == null) {
    return null;
  }
  return _languageMap[language] ?? language;
}

const _languageMap = <String, String>{
  'afrikaans': 'af',
  'arabic': 'ar',
  'armenian': 'hy',
  'azerbaijani': 'az',
  'belarusian': 'be',
  'bosnian': 'bs',
  'bulgarian': 'bg',
  'catalan': 'ca',
  'chinese': 'zh',
  'croatian': 'hr',
  'czech': 'cs',
  'danish': 'da',
  'dutch': 'nl',
  'english': 'en',
  'estonian': 'et',
  'finnish': 'fi',
  'french': 'fr',
  'galician': 'gl',
  'german': 'de',
  'greek': 'el',
  'hebrew': 'he',
  'hindi': 'hi',
  'hungarian': 'hu',
  'icelandic': 'is',
  'indonesian': 'id',
  'italian': 'it',
  'japanese': 'ja',
  'kannada': 'kn',
  'kazakh': 'kk',
  'korean': 'ko',
  'latvian': 'lv',
  'lithuanian': 'lt',
  'macedonian': 'mk',
  'malay': 'ms',
  'marathi': 'mr',
  'maori': 'mi',
  'nepali': 'ne',
  'norwegian': 'no',
  'persian': 'fa',
  'polish': 'pl',
  'portuguese': 'pt',
  'romanian': 'ro',
  'russian': 'ru',
  'serbian': 'sr',
  'slovak': 'sk',
  'slovenian': 'sl',
  'spanish': 'es',
  'swahili': 'sw',
  'swedish': 'sv',
  'tagalog': 'tl',
  'tamil': 'ta',
  'thai': 'th',
  'turkish': 'tr',
  'ukrainian': 'uk',
  'urdu': 'ur',
  'vietnamese': 'vi',
  'welsh': 'cy',
};

Future<T> _postMultipartToApi<T>({
  required Uri url,
  required Map<String, String> headers,
  required Map<String, String> fields,
  required List<http.MultipartFile> files,
  required ResponseHandler<T> successHandler,
  required FailedResponseHandler failureHandler,
  http.Client? client,
  CancellationSignal? cancellation,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();

  final request = http.AbortableMultipartRequest(
    'POST',
    url,
    abortTrigger: cancellation?.whenCancelled,
  )
    ..headers.addAll(headers)
    ..fields.addAll(fields)
    ..files.addAll(files);

  try {
    final http.StreamedResponse response;
    try {
      response = await httpClient.send(request);
    } catch (error) {
      if (error is http.RequestAbortedException) {
        rethrow;
      }
      throw mapTransportError(error, url: url, requestBody: fields);
    }

    final ctx = ResponseContext(
      url: url,
      requestBody: fields,
      response: response,
    );

    final statusCode = response.statusCode;
    if (statusCode >= 200 && statusCode < 300) {
      return await successHandler(ctx);
    }
    throw await failureHandler(ctx);
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}
