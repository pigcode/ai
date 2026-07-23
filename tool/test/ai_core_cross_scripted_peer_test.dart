import 'package:pigcode_ai/pigcode_ai.dart' as ai;
import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart' as anthropic;
import 'package:pigcode_ai_openai/pigcode_ai_openai.dart' as openai;
import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart'
    as compatible;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;

// Compatibility fixture (unit): P1-CROSS-01
// Compatibility fixture (unit): P1-CROSS-02
// Compatibility fixture (unit): P1-CROSS-03
// Compatibility fixture (unit): P1-CROSS-04
// Compatibility fixture (unit): P1-CROSS-05
// Compatibility fixture (scripted-peer): P1-CROSS-01
// Compatibility fixture (scripted-peer): P1-CROSS-02
// Compatibility fixture (scripted-peer): P1-CROSS-03
// Compatibility fixture (scripted-peer): P1-CROSS-04
// Compatibility fixture (scripted-peer): P1-CROSS-05
Future<void> main() async {
  _verifySharedProviderIdentity();
  _verifyTypedMetadata();
  _verifySharedErrors();
  await _verifySharedCancellation();
  _verifyPortablePublicSurface();
  print('PASS AI Core cross-package scripted peer');
}

void _verifySharedProviderIdentity() {
  final implementations = <provider.Provider>[
    openai.createOpenAi(apiKey: 'fixed-test-key'),
    compatible.createOpenAiCompatible(
      name: 'fixed-compatible',
      baseUrl: 'https://example.invalid/v1',
    ),
    anthropic.createAnthropic(apiKey: 'fixed-test-key'),
  ];

  for (final implementation in implementations) {
    final ai.Provider coreView = implementation;
    _expect(
      identical(coreView, implementation),
      'The AI barrel changed the neutral Provider type identity.',
    );
  }

  final models = <provider.LanguageModel>[
    implementations[0].languageModel('gpt-4o-mini'),
    implementations[1].languageModel('fixed-model'),
    implementations[2].languageModel('claude-sonnet-4-5'),
  ];
  for (final model in models) {
    final ai.LanguageModel coreView = model;
    _expect(
      identical(coreView, model),
      'An adapter changed the neutral LanguageModel type identity.',
    );
  }
}

void _verifyTypedMetadata() {
  const provider.ProviderMetadata contractMetadata =
      <String, provider.JsonObject>{
    'fixed-peer': <String, Object?>{
      'traceId': 'cross-scripted-1',
      'nested': <String, Object?>{'kept': true},
    },
  };
  const ai.ProviderMetadata coreMetadata = contractMetadata;
  const provider.LanguageModelGenerateResult contractResult =
      provider.LanguageModelGenerateResult(
    content: <provider.LanguageModelContent>[
      provider.TextContent(
        'metadata',
        providerMetadata: contractMetadata,
      ),
    ],
    finishReason: provider.LanguageModelFinishReason(
      provider.FinishReasonType.stop,
    ),
    usage: provider.LanguageModelUsage(
      inputTokens: provider.InputTokens(),
      outputTokens: provider.OutputTokens(),
    ),
    warnings: <provider.Warning>[],
    providerMetadata: contractMetadata,
  );
  const ai.LanguageModelGenerateResult coreResult = contractResult;

  _expect(
    identical(coreResult.providerMetadata, coreMetadata),
    'Provider metadata lost its typed identity at the AI boundary.',
  );
  _expect(
    coreResult.providerMetadata?['fixed-peer']?['nested']
        is Map<String, Object?>,
    'Nested provider metadata was flattened or erased.',
  );
}

void _verifySharedErrors() {
  final adapterErrors = <Object>[
    _captureError(
      () => openai.createOpenAi(
        apiKey: 'fixed-test-key',
        baseUrl: '',
      ),
    ),
    _captureError(
      () => compatible.createOpenAiCompatible(
        name: 'fixed-compatible',
        baseUrl: '',
      ),
    ),
    _captureError(
      () => anthropic.createAnthropic(
        apiKey: 'fixed-test-key',
        baseUrl: '',
      ),
    ),
  ];
  for (final error in adapterErrors) {
    _expect(
      error.runtimeType == provider.InvalidArgumentError &&
          error.runtimeType == ai.InvalidArgumentError,
      'An adapter did not expose the shared InvalidArgumentError type.',
    );
  }

  final provider.ApiCallError utilityError = utils.mapTransportError(
    StateError('fixed transport failure'),
    url: Uri.parse('https://example.invalid/v1'),
  );
  final ai.ApiCallError coreError = utilityError;
  _expect(
    identical(coreError, utilityError) && coreError.isRetryable,
    'Provider utilities changed the shared ApiCallError contract.',
  );
}

Future<void> _verifySharedCancellation() async {
  final controller = ai.CancellationController();
  final provider.CancellationSignal contractSignal = controller.signal;
  final pending = utils.delayCancellable(
    const Duration(seconds: 5),
    cancellation: contractSignal,
  );
  final reason = StateError('fixed scripted cancellation');
  controller.cancel(reason);

  final error = await _captureFutureError(pending);
  _expect(error is StateError, 'Cancellation was wrapped as an API error.');
  _expect(
    identical(contractSignal.reason, reason),
    'Cancellation reason identity was not preserved across packages.',
  );
}

void _verifyPortablePublicSurface() {
  final prompt = ai.Prompt(prompt: 'portable');
  final normalized = utils.withoutTrailingSlash('https://example.invalid/v1/');
  final openAiCapabilities =
      openai.getOpenAiLanguageModelCapabilities('gpt-4o-mini');
  final compatibleReason = compatible.mapOpenAiCompatibleFinishReason('stop');
  final anthropicCapabilities =
      anthropic.getAnthropicModelCapabilities('claude-sonnet-4-5');

  _expect(prompt.prompt == 'portable', 'AI portable prompt surface failed.');
  _expect(
    normalized == 'https://example.invalid/v1',
    'Provider utility portable surface failed.',
  );
  _expect(
    openAiCapabilities.systemMessageMode == openai.SystemMessageMode.system,
    'OpenAI capabilities were not reachable through its public barrel.',
  );
  _expect(
    compatibleReason.unified == provider.FinishReasonType.stop,
    'OpenAI-compatible finish reasons lost the neutral enum identity.',
  );
  _expect(
    anthropicCapabilities.maxOutputTokens > 0,
    'Anthropic capabilities were not reachable through its public barrel.',
  );
}

Object _captureError(void Function() action) {
  try {
    action();
  } on Object catch (error) {
    return error;
  }
  throw StateError('Expected the action to throw.');
}

Future<Object?> _captureFutureError(Future<void> future) async {
  try {
    await future;
  } on Object catch (error) {
    return error;
  }
  return null;
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
