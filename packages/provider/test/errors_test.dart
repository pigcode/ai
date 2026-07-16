import 'package:pigcode_ai_provider/src/errors/errors.dart';
import 'package:pigcode_ai_provider/src/language_model/finish_reason.dart';
import 'package:pigcode_ai_provider/src/language_model/results.dart';
import 'package:pigcode_ai_provider/src/language_model/usage.dart';
import 'package:test/test.dart';

void main() {
  group('ApiCallError.isRetryable', () {
    ApiCallError makeError({int? statusCode, bool? isRetryable}) {
      return ApiCallError(
        message: 'call failed',
        url: 'https://example.test/v1/chat',
        requestBody: '{"model":"x"}',
        statusCode: statusCode,
        isRetryable: isRetryable,
      );
    }

    test('defaults to retryable for 408/409/429 and any 5xx', () {
      expect(makeError(statusCode: 408).isRetryable, isTrue);
      expect(makeError(statusCode: 409).isRetryable, isTrue);
      expect(makeError(statusCode: 429).isRetryable, isTrue);
      expect(makeError(statusCode: 500).isRetryable, isTrue);
      expect(makeError(statusCode: 503).isRetryable, isTrue);
    });

    test('defaults to non-retryable for other 4xx and missing status', () {
      expect(makeError(statusCode: 400).isRetryable, isFalse);
      expect(makeError(statusCode: 404).isRetryable, isFalse);
      expect(makeError(statusCode: null).isRetryable, isFalse);
    });

    test('explicit isRetryable overrides the status-based default', () {
      // 400 is not retryable by default, but explicit true wins.
      expect(makeError(statusCode: 400, isRetryable: true).isRetryable, isTrue);
      // 500 is retryable by default, but explicit false wins.
      expect(
          makeError(statusCode: 500, isRetryable: false).isRetryable, isFalse);
    });

    test('carries wire data and yields a useful toString', () {
      final error = ApiCallError(
        message: 'bad gateway',
        url: 'https://example.test/v1/chat',
        requestBody: '{"model":"x"}',
        statusCode: 502,
        responseHeaders: const {'content-type': 'application/json'},
        responseBody: '{"error":"upstream"}',
        data: const {'code': 'upstream_error'},
      );

      expect(error, isA<AiError>());
      expect(error, isA<Exception>());
      expect(error.statusCode, 502);
      expect(error.responseHeaders, const {'content-type': 'application/json'});
      expect(error.responseBody, '{"error":"upstream"}');
      expect(error.data, const {'code': 'upstream_error'});

      final text = error.toString();
      expect(text, contains('ApiCallError'));
      expect(text, contains('bad gateway'));
      expect(text, contains('502'));
    });
  });

  group('NoSuchModelError', () {
    test('exposes modelId and modelType and a default message', () {
      const error = NoSuchModelError(
        modelId: 'gpt-unknown',
        modelType: ModelType.languageModel,
      );

      expect(error, isA<AiError>());
      expect(error.modelId, 'gpt-unknown');
      expect(error.modelType, ModelType.languageModel);
      expect(error.message, contains('gpt-unknown'));
      expect(error.message, contains('languageModel'));

      final text = error.toString();
      expect(text, contains('NoSuchModelError'));
      expect(text, contains('gpt-unknown'));
    });

    test('honors an explicit message override', () {
      const error = NoSuchModelError(
        modelId: 'x',
        modelType: ModelType.embeddingModel,
        message: 'custom not-found text',
      );
      expect(error.message, 'custom not-found text');
      expect(error.modelType, ModelType.embeddingModel);
    });
  });

  group('NoSuchProviderError', () {
    test('exposes providerId, available providers and model diagnostics', () {
      final error = NoSuchProviderError(
        modelId: 'google',
        modelType: ModelType.languageModel,
        providerId: 'google',
        availableProviders: ['openai', 'anthropic'],
      );

      expect(error, isA<NoSuchModelError>());
      expect(error, isA<AiError>());
      expect(error.modelId, 'google');
      expect(error.modelType, ModelType.languageModel);
      expect(error.providerId, 'google');
      expect(error.availableProviders, ['openai', 'anthropic']);
      expect(error.message, contains('No such provider: google'));
      expect(error.message, contains('openai'));
      expect(error.message, contains('anthropic'));
    });
  });

  group('NoSuchProviderReferenceError', () {
    test('exposes provider, reference and default message', () {
      const reference = <String, String>{
        'openai': 'file-1',
        'anthropic': 'file-2',
      };
      final error = NoSuchProviderReferenceError(
        provider: 'google',
        reference: reference,
      );

      expect(error, isA<AiError>());
      expect(error.provider, 'google');
      expect(error.reference, reference);
      expect(error.message, contains("provider 'google'"));
      expect(error.message, contains('openai'));
      expect(error.message, contains('anthropic'));
    });
  });

  group('other AiError subclasses', () {
    test('are all AiError/Exception and carry their data', () {
      const invalidPrompt = InvalidPromptError(
        prompt: <String>[],
        message: 'prompt is empty',
      );
      expect(invalidPrompt, isA<AiError>());
      expect(invalidPrompt.prompt, <String>[]);

      const unsupported = UnsupportedFunctionalityError(
        functionality: 'logprobs',
      );
      expect(unsupported.functionality, 'logprobs');
      expect(unsupported.message, contains('logprobs'));

      const invalidArg = InvalidArgumentError(
        argument: 'temperature',
        message: 'must be between 0 and 2',
      );
      expect(invalidArg.argument, 'temperature');

      const invalidData = InvalidResponseDataError(
        data: <String, Object?>{'x': 1},
      );
      expect(invalidData.data, <String, Object?>{'x': 1});

      const jsonParse = JsonParseError(text: 'not json', cause: 'boom');
      expect(jsonParse.text, 'not json');
      expect(jsonParse.cause, 'boom');

      const typeValidation = TypeValidationError(value: 42, cause: 'wrong');
      expect(typeValidation.value, 42);
      expect(typeValidation.cause, 'wrong');

      const noContent = NoContentGeneratedError();
      expect(noContent, isA<AiError>());
      expect(noContent.message, isNotEmpty);

      const emptyBody = EmptyResponseBodyError();
      expect(emptyBody, isA<AiError>());
      expect(emptyBody.message, isNotEmpty);

      const loadKey = LoadApiKeyError(message: 'missing OPENAI_API_KEY');
      expect(loadKey.message, 'missing OPENAI_API_KEY');

      const loadSetting = LoadSettingError(message: 'missing baseUrl');
      expect(loadSetting.message, 'missing baseUrl');
    });
  });

  group('NoOutputGeneratedError', () {
    test('has default message and optional cause', () {
      const cause = JsonParseError(text: '{');
      const error = NoOutputGeneratedError(cause: cause);

      expect(error, isA<AiError>());
      expect(error.message, 'No output generated.');
      expect(error.cause, same(cause));
      expect(error.toString(), contains('NoOutputGeneratedError'));
    });
  });

  group('NoObjectGeneratedError', () {
    test('has default message and optional cause', () {
      const cause = JsonParseError(text: '{');
      const error = NoObjectGeneratedError(cause: cause);

      expect(error, isA<AiError>());
      expect(error.message, 'No object generated.');
      expect(error.cause, same(cause));
      expect(error.toString(), contains('NoObjectGeneratedError'));
    });

    test('keeps text/response/usage/finishReason diagnostics', () {
      const cause = TypeValidationError(value: {'bad': true});
      const response = ResponseInfo(id: 'r1', modelId: 'm1');
      const usage = LanguageModelUsage(
        inputTokens: InputTokens(total: 2),
        outputTokens: OutputTokens(total: 3),
      );
      const finishReason = LanguageModelFinishReason(FinishReasonType.stop);
      const error = NoObjectGeneratedError(
        message: 'No object generated: response did not match schema.',
        cause: cause,
        text: '{"bad":true}',
        response: response,
        usage: usage,
        finishReason: finishReason,
      );

      expect(error, isA<AiError>());
      expect(
          error.message, 'No object generated: response did not match schema.');
      expect(error.cause, same(cause));
      expect(error.text, '{"bad":true}');
      expect(error.response, response);
      expect(error.usage, usage);
      expect(error.finishReason, finishReason);
    });
  });

  group('TooManyEmbeddingValuesForCallError', () {
    test('exposes all fields and a fully composed message', () {
      final error = TooManyEmbeddingValuesForCallError(
        provider: 'openai.embedding',
        modelId: 'text-embedding-3-small',
        maxEmbeddingsPerCall: 2048,
        valuesCount: 3000,
      );

      expect(error, isA<AiError>());
      expect(error, isA<Exception>());
      expect(error.provider, 'openai.embedding');
      expect(error.modelId, 'text-embedding-3-small');
      expect(error.maxEmbeddingsPerCall, 2048);
      expect(error.valuesCount, 3000);
      expect(
        error.message,
        'Too many values for a single embedding call. '
        'The openai.embedding model "text-embedding-3-small" can only embed up to '
        '2048 values per call, but 3000 values were provided.',
      );

      final text = error.toString();
      expect(text, contains('TooManyEmbeddingValuesForCallError'));
      expect(text, contains('text-embedding-3-small'));
    });
  });
}
