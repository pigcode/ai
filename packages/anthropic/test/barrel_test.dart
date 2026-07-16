import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('barrel 导出完整性', () {
    test('createAnthropic 与 AnthropicProvider 经 barrel 可达', () {
      final provider = createAnthropic(apiKey: 'k');
      expect(provider, isA<AnthropicProvider>());
      expect(provider, isA<Provider>());
    });

    test('AnthropicConfig 经 barrel 可直接构造', () {
      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: () => const {},
      );
      expect(config.providerName, 'anthropic.messages');
    });

    test('AnthropicMessagesLanguageModel 经 barrel 可直接构造', () {
      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: () => const {},
      );
      final model =
          AnthropicMessagesLanguageModel('claude-sonnet-4-5', config: config);
      expect(model, isA<LanguageModel>());
      expect(model.provider, 'anthropic.messages');
    });

    test('AnthropicFiles/AnthropicSkills 经 barrel 可直接构造', () {
      final config = AnthropicConfig(
        providerName: 'anthropic.messages',
        baseUrl: 'https://api.anthropic.com/v1',
        headers: () => const {},
      );

      expect(AnthropicFiles(config: config), isA<Files>());
      expect(AnthropicSkills(config: config), isA<Skills>());
    });

    test('getAnthropicModelCapabilities 经 barrel 可达', () {
      final capabilities = getAnthropicModelCapabilities('claude-fable-5');
      expect(capabilities, isA<AnthropicModelCapabilities>());
    });

    test('resolveAnthropicProviderOptions 经 barrel 可达', () {
      final resolved = resolveAnthropicProviderOptions(
        'anthropic.messages',
        null,
      );
      expect(resolved.options, isA<AnthropicMessagesProviderOptions>());
      expect(resolved.usedCustomProviderKey, isFalse);
    });

    test('convertToAnthropicMessages 与 AnthropicPromptResult 经 barrel 可达', () {
      final result = convertToAnthropicMessages(
        prompt: const <LanguageModelMessage>[
          UserMessage(<UserContentPart>[TextPart('hello')]),
        ],
        sendReasoning: false,
      );
      expect(result, isA<AnthropicPromptResult>());
      expect(result.messages, hasLength(1));
    });

    test('CacheControlValidator 经 barrel 可直接构造', () {
      expect(CacheControlValidator(), isA<CacheControlValidator>());
    });

    test('sanitizeJsonSchema 经 barrel 可达', () {
      final sanitized = sanitizeJsonSchema(const {'type': 'object'});
      expect(sanitized['type'], 'object');
    });

    test('prepareAnthropicTools 与 AnthropicToolsResult 经 barrel 可达', () {
      final result = prepareAnthropicTools(
        tools: null,
        toolChoice: null,
        disableParallelToolUse: null,
        getCacheControl: (_) => null,
        supportsStructuredOutput: false,
        supportsStrictTools: false,
      );
      expect(result, isA<AnthropicToolsResult>());
    });

    test('mapAnthropicStopReason 经 barrel 可达', () {
      final reason = mapAnthropicStopReason(
        'end_turn',
        isJsonResponseFromTool: false,
      );
      expect(reason.unified, FinishReasonType.stop);
    });

    test('convertAnthropicUsage 经 barrel 可达', () {
      final usage = convertAnthropicUsage(const {
        'input_tokens': 1,
        'output_tokens': 2,
      });
      expect(usage, isA<LanguageModelUsage>());
    });

    test('anthropicFailedResponseHandler 经 barrel 可达', () {
      expect(anthropicFailedResponseHandler(), isNotNull);
    });

    test(
      'web_search/web_fetch 顶层工厂、选项类与 anthropicTools 聚合入口经 barrel 可达',
      () {
        expect(webSearch_20250305().id, 'anthropic.web_search_20250305');
        expect(webSearch_20260209().id, 'anthropic.web_search_20260209');
        expect(webFetch_20250910().id, 'anthropic.web_fetch_20250910');
        expect(webFetch_20260209().id, 'anthropic.web_fetch_20260209');
        expect(
          const AnthropicWebSearchUserLocation(city: 'SF').toJson(),
          {'type': 'approximate', 'city': 'SF'},
        );
        expect(
          const AnthropicWebFetchCitations(enabled: true).toJson(),
          {'enabled': true},
        );
        expect(anthropicTools, isA<AnthropicTools>());
        expect(
          anthropicTools.webSearch_20250305(),
          webSearch_20250305(),
        );
      },
    );

    test(
      'computer/text_editor/bash 顶层工厂与 anthropicTools 聚合入口经 barrel 可达',
      () {
        expect(
          computer_20241022(displayWidthPx: 1024, displayHeightPx: 768).id,
          'anthropic.computer_20241022',
        );
        expect(
          computer_20250124(displayWidthPx: 1024, displayHeightPx: 768).id,
          'anthropic.computer_20250124',
        );
        expect(
          computer_20251124(displayWidthPx: 1024, displayHeightPx: 768).id,
          'anthropic.computer_20251124',
        );
        expect(textEditor_20241022().id, 'anthropic.text_editor_20241022');
        expect(textEditor_20250124().id, 'anthropic.text_editor_20250124');
        expect(textEditor_20250728().id, 'anthropic.text_editor_20250728');
        expect(bash_20241022().id, 'anthropic.bash_20241022');
        expect(bash_20250124().id, 'anthropic.bash_20250124');

        expect(
          anthropicTools.computer_20241022(
            displayWidthPx: 1024,
            displayHeightPx: 768,
          ),
          computer_20241022(displayWidthPx: 1024, displayHeightPx: 768),
        );
        expect(
          anthropicTools.computer_20250124(
            displayWidthPx: 1024,
            displayHeightPx: 768,
          ),
          computer_20250124(displayWidthPx: 1024, displayHeightPx: 768),
        );
        expect(
          anthropicTools.computer_20251124(
            displayWidthPx: 1024,
            displayHeightPx: 768,
          ),
          computer_20251124(displayWidthPx: 1024, displayHeightPx: 768),
        );
        expect(
          anthropicTools.textEditor_20241022(),
          textEditor_20241022(),
        );
        expect(
          anthropicTools.textEditor_20250124(),
          textEditor_20250124(),
        );
        expect(
          anthropicTools.textEditor_20250728(),
          textEditor_20250728(),
        );
        expect(anthropicTools.bash_20241022(), bash_20241022());
        expect(anthropicTools.bash_20250124(), bash_20250124());
      },
    );

    test(
      'code_execution/memory/tool_search/advisor 顶层工厂与 '
      'anthropicTools 聚合入口经 barrel 可达',
      () {
        expect(
          codeExecution_20250522().id,
          'anthropic.code_execution_20250522',
        );
        expect(
          codeExecution_20250825().id,
          'anthropic.code_execution_20250825',
        );
        expect(
          codeExecution_20260120().id,
          'anthropic.code_execution_20260120',
        );
        expect(memory_20250818().id, 'anthropic.memory_20250818');
        expect(
          toolSearchRegex_20251119().id,
          'anthropic.tool_search_regex_20251119',
        );
        expect(
          toolSearchBm25_20251119().id,
          'anthropic.tool_search_bm25_20251119',
        );
        expect(
          advisor_20260301(model: 'claude-opus-4-7').id,
          'anthropic.advisor_20260301',
        );
        expect(
          const AnthropicAdvisorCaching(ttl: '5m').toJson(),
          {'type': 'ephemeral', 'ttl': '5m'},
        );

        expect(
          anthropicTools.codeExecution_20250522(),
          codeExecution_20250522(),
        );
        expect(
          anthropicTools.codeExecution_20250825(),
          codeExecution_20250825(),
        );
        expect(
          anthropicTools.codeExecution_20260120(),
          codeExecution_20260120(),
        );
        expect(anthropicTools.memory_20250818(), memory_20250818());
        expect(
          anthropicTools.toolSearchRegex_20251119(),
          toolSearchRegex_20251119(),
        );
        expect(
          anthropicTools.toolSearchBm25_20251119(),
          toolSearchBm25_20251119(),
        );
        expect(
          anthropicTools.advisor_20260301(model: 'claude-opus-4-7'),
          advisor_20260301(model: 'claude-opus-4-7'),
        );
      },
    );
  });
}
