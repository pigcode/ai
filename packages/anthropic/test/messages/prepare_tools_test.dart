import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

/// 测试辅助:用缺省参数调用 [prepareAnthropicTools],单测只需覆写关心的参数。
AnthropicToolsResult prepare({
  List<LanguageModelTool>? tools,
  ToolChoice? toolChoice,
  bool? disableParallelToolUse,
  ToolCacheControlResolver? getCacheControl,
  bool supportsStructuredOutput = false,
  bool supportsStrictTools = false,
  bool defaultEagerInputStreaming = false,
}) {
  return prepareAnthropicTools(
    tools: tools,
    toolChoice: toolChoice,
    disableParallelToolUse: disableParallelToolUse,
    getCacheControl: getCacheControl ?? (_) => null,
    supportsStructuredOutput: supportsStructuredOutput,
    supportsStrictTools: supportsStrictTools,
    defaultEagerInputStreaming: defaultEagerInputStreaming,
  );
}

void main() {
  group('prepareAnthropicTools 归一化', () {
    test('tools:null → 全空结果', () {
      final result = prepare(tools: null);

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isEmpty);
      expect(result.betas, isEmpty);
    });

    test('tools:const [] 归一化为 null,同全空结果', () {
      final result = prepare(tools: const []);

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isEmpty);
      expect(result.betas, isEmpty);
    });

    test('tools:null 时不处理 toolChoice,toolChoice 仍为 null', () {
      final result = prepare(tools: null, toolChoice: const ToolChoiceAuto());

      expect(result.toolChoice, isNull);
    });
  });

  group('prepareAnthropicTools function tool 映射', () {
    test('最小 function tool → 扁平 wire 对象,可选键全部缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            description: 'fetch weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(result.tools, [
        {
          'name': 'get_weather',
          'description': 'fetch weather',
          'input_schema': {'type': 'object'},
        },
      ]);
      final wireTool = result.tools!.single;
      expect(wireTool.containsKey('cache_control'), isFalse);
      expect(wireTool.containsKey('eager_input_streaming'), isFalse);
      expect(wireTool.containsKey('strict'), isFalse);
      expect(wireTool.containsKey('defer_loading'), isFalse);
      expect(wireTool.containsKey('allowed_callers'), isFalse);
      expect(wireTool.containsKey('input_examples'), isFalse);
    });

    test('description 为 null 时键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(result.tools!.single.containsKey('description'), isFalse);
    });
  });

  group('prepareAnthropicTools cache_control', () {
    test('resolver 返回非 null 时写入 cache_control', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        getCacheControl: (_) => {'type': 'ephemeral'},
      );

      expect(result.tools!.single['cache_control'], {'type': 'ephemeral'});
    });

    test('resolver 返回 null 时键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        getCacheControl: (_) => null,
      );

      expect(result.tools!.single.containsKey('cache_control'), isFalse);
    });
  });

  group('prepareAnthropicTools eager_input_streaming 三态', () {
    test('工具级选项 true → 发 true', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            providerOptions: {
              'anthropic': {'eagerInputStreaming': true},
            },
          ),
        ],
      );

      expect(result.tools!.single['eager_input_streaming'], true);
    });

    test('工具未设且 defaultEagerInputStreaming:true → 发 true', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        defaultEagerInputStreaming: true,
      );

      expect(result.tools!.single['eager_input_streaming'], true);
    });

    test('工具显式 false 且 default true → 键完全缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            providerOptions: {
              'anthropic': {'eagerInputStreaming': false},
            },
          ),
        ],
        defaultEagerInputStreaming: true,
      );

      expect(
        result.tools!.single.containsKey('eager_input_streaming'),
        isFalse,
      );
    });

    test('default 缺省且工具未设 → 键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(
        result.tools!.single.containsKey('eager_input_streaming'),
        isFalse,
      );
    });
  });

  group('prepareAnthropicTools strict 门控', () {
    test('supportsStrictTools:true 且 strict:true → 发 strict:true', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            strict: true,
          ),
        ],
        supportsStrictTools: true,
      );

      expect(result.tools!.single['strict'], true);
      expect(result.warnings, isEmpty);
    });

    test('strict:null → 键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        supportsStrictTools: true,
      );

      expect(result.tools!.single.containsKey('strict'), isFalse);
    });

    test('supportsStrictTools:false 且 strict:true → 键缺席 + warning', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            strict: true,
          ),
        ],
        supportsStrictTools: false,
      );

      expect(result.tools!.single.containsKey('strict'), isFalse);
      expect(result.warnings, [
        const UnsupportedWarning(
          'strict',
          details: "Tool 'get_weather' has strict: true, but strict mode is "
              'not supported by this provider. The strict property will be '
              'ignored.',
        ),
      ]);
    });
  });

  group('prepareAnthropicTools defer_loading / allowed_callers', () {
    test('deferLoading 显式 false 也发送 defer_loading:false', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            providerOptions: {
              'anthropic': {'deferLoading': false},
            },
          ),
        ],
      );

      expect(result.tools!.single['defer_loading'], false);
    });

    test('deferLoading 未设时键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(result.tools!.single.containsKey('defer_loading'), isFalse);
    });

    test('allowedCallers 设置时发送 allowed_callers', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            providerOptions: {
              'anthropic': {
                'allowedCallers': ['direct'],
              },
            },
          ),
        ],
      );

      expect(result.tools!.single['allowed_callers'], ['direct']);
    });

    test('allowedCallers 未设时键缺席', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
      );

      expect(result.tools!.single.containsKey('allowed_callers'), isFalse);
    });
  });

  group('prepareAnthropicTools input_examples', () {
    test('inputExamples 裸列表直接透传为 input_examples', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            inputExamples: [
              {'city': 'SF'},
            ],
          ),
        ],
      );

      expect(result.tools!.single['input_examples'], [
        {'city': 'SF'},
      ]);
    });
  });

  group('prepareAnthropicTools betas 收集', () {
    test('存在 function tool 且 supportsStructuredOutput:true → 含结构化输出 beta', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        supportsStructuredOutput: true,
      );

      expect(result.betas, contains('structured-outputs-2025-11-13'));
    });

    test('supportsStructuredOutput:false → 不含结构化输出 beta', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
        ],
        supportsStructuredOutput: false,
      );

      expect(result.betas, isNot(contains('structured-outputs-2025-11-13')));
    });

    test('inputExamples 非 null → 含 advanced-tool-use beta', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            inputExamples: [
              {'city': 'SF'},
            ],
          ),
        ],
      );

      expect(result.betas, contains('advanced-tool-use-2025-11-20'));
    });

    test('allowedCallers 非 null → 含 advanced-tool-use beta', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            providerOptions: {
              'anthropic': {
                'allowedCallers': ['direct'],
              },
            },
          ),
        ],
      );

      expect(result.betas, contains('advanced-tool-use-2025-11-20'));
    });

    test('双命中时恰好两元素 Set', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            inputExamples: [
              {'city': 'SF'},
            ],
          ),
        ],
        supportsStructuredOutput: true,
      );

      expect(result.betas, {
        'structured-outputs-2025-11-13',
        'advanced-tool-use-2025-11-20',
      });
    });
  });

  group('prepareAnthropicTools toolChoice 映射', () {
    // 复用的最小 function tool,让 tools 走正常返回路径。
    const weatherTool = FunctionTool(
      name: 'get_weather',
      inputSchema: JsonSchema({'type': 'object'}),
    );

    test('toolChoice:null 且 disableParallelToolUse:null → toolChoice null', () {
      final result = prepare(tools: [weatherTool]);

      expect(result.tools, hasLength(1));
      expect(result.toolChoice, isNull);
    });

    test('toolChoice:null 且 disableParallelToolUse:true → auto + 关闭并行', () {
      final result = prepare(
        tools: [weatherTool],
        disableParallelToolUse: true,
      );

      expect(result.toolChoice, {
        'type': 'auto',
        'disable_parallel_tool_use': true,
      });
    });

    test('toolChoice:null 且 disableParallelToolUse:false → toolChoice null',
        () {
      // 上游 null-choice 分支仅 truthy 触发,falsy → undefined(:389-396);
      // 与显式 choice 分支的行为差异是上游语义,须分别断言。
      final result = prepare(
        tools: [weatherTool],
        disableParallelToolUse: false,
      );

      expect(result.toolChoice, isNull);
    });

    test('ToolChoiceAuto 且 disableParallelToolUse:null → 不含并行键', () {
      final result = prepare(
        tools: [weatherTool],
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.toolChoice, {'type': 'auto'});
      expect(
        result.toolChoice!.containsKey('disable_parallel_tool_use'),
        isFalse,
      );
    });

    test('ToolChoiceAuto 且 disableParallelToolUse:false → 显式 false 保留', () {
      final result = prepare(
        tools: [weatherTool],
        toolChoice: const ToolChoiceAuto(),
        disableParallelToolUse: false,
      );

      expect(result.toolChoice, {
        'type': 'auto',
        'disable_parallel_tool_use': false,
      });
    });

    test('ToolChoiceRequired → wire type any', () {
      final result = prepare(
        tools: [weatherTool],
        toolChoice: const ToolChoiceRequired(),
      );

      expect(result.toolChoice, {'type': 'any'});
    });

    test('ToolChoiceTool + disableParallelToolUse:true → type tool 带工具名', () {
      final result = prepare(
        tools: [weatherTool],
        toolChoice: const ToolChoiceTool('get_weather'),
        disableParallelToolUse: true,
      );

      expect(result.toolChoice, {
        'type': 'tool',
        'name': 'get_weather',
        'disable_parallel_tool_use': true,
      });
    });

    test('ToolChoiceNone → tools/toolChoice 均 null,warnings/betas 不回滚', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
            inputExamples: [
              {'city': 'SF'},
            ],
          ),
          const ProviderTool(
            id: 'anthropic.text_editor_20250429',
            name: 'str_replace_based_edit_tool',
            args: {},
          ),
        ],
        toolChoice: const ToolChoiceNone(),
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isNotEmpty);
      expect(result.betas, contains('advanced-tool-use-2025-11-20'));
    });
  });

  group('prepareAnthropicTools provider tools — web', () {
    test('webSearch_20250305 → camel→snake wire 对象,无值字段缺席,无 beta', () {
      final result = prepare(
        tools: [
          webSearch_20250305(
            maxUses: 3,
            userLocation: const AnthropicWebSearchUserLocation(city: 'SF'),
          ),
        ],
      );

      expect(result.tools, [
        {
          'type': 'web_search_20250305',
          'name': 'web_search',
          'max_uses': 3,
          'user_location': {'type': 'approximate', 'city': 'SF'},
        },
      ]);
      expect(result.betas, isEmpty);
    });

    test('webSearch_20260209 → type 正确且 betas 含 code-execution-web-tools', () {
      final result = prepare(tools: [webSearch_20260209()]);

      expect(result.tools!.single['type'], 'web_search_20260209');
      expect(
        result.betas,
        contains('code-execution-web-tools-2026-02-09'),
      );
    });

    test(
        'webFetch_20250910 → wire 对象含 citations/max_content_tokens 且 '
        'betas 含 web-fetch beta', () {
      final result = prepare(
        tools: [
          webFetch_20250910(
            citations: const AnthropicWebFetchCitations(enabled: true),
            maxContentTokens: 100,
          ),
        ],
      );

      expect(result.tools, [
        {
          'type': 'web_fetch_20250910',
          'name': 'web_fetch',
          'citations': {'enabled': true},
          'max_content_tokens': 100,
        },
      ]);
      expect(result.betas, contains('web-fetch-2025-09-10'));
    });

    test('webFetch_20260209 → betas 含 code-execution-web-tools', () {
      final result = prepare(tools: [webFetch_20260209()]);

      expect(
        result.betas,
        contains('code-execution-web-tools-2026-02-09'),
      );
    });

    test('未知 provider id 行为不变:仍 UnsupportedWarning + 丢弃', () {
      // text_editor_20250429 是 deprecated 版本,8 版决策(D3)排除,
      // 故永远落入 default 分支,可作为"未知 id"稳定样本。
      final result = prepare(
        tools: [
          const ProviderTool(
            id: 'anthropic.text_editor_20250429',
            name: 'str_replace_based_edit_tool',
            args: {},
          ),
        ],
      );

      expect(result.tools, isNull);
      expect(result.warnings, [
        const UnsupportedWarning(
          'provider-defined tool anthropic.text_editor_20250429',
        ),
      ]);
    });

    test('web 工具与 FunctionTool 混合 → 两者都在 tools 数组,顺序保持', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
          webSearch_20250305(),
        ],
      );

      expect(result.tools, [
        {
          'name': 'get_weather',
          'input_schema': {'type': 'object'},
        },
        {
          'type': 'web_search_20250305',
          'name': 'web_search',
        },
      ]);
    });

    test('非法 args 本地抛:maxUses 类型错误', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.web_search_20260209',
              name: 'web_search',
              args: {'maxUses': 'three'},
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('非法 args 本地抛:userLocation.type 字面量不符', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.web_search_20260209',
              name: 'web_search',
              args: {
                'userLocation': {'type': 'exact'},
              },
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('prepareAnthropicTools ProviderTool 丢弃', () {
    test('provider 内置工具推 unsupported warning 并被丢弃(文案带 id)', () {
      final result = prepare(
        tools: [
          const FunctionTool(
            name: 'get_weather',
            inputSchema: JsonSchema({'type': 'object'}),
          ),
          const ProviderTool(
            id: 'anthropic.text_editor_20250429',
            name: 'str_replace_based_edit_tool',
            args: {},
          ),
        ],
      );

      expect(result.tools, hasLength(1));
      expect(result.tools!.single['name'], 'get_weather');
      expect(result.warnings, [
        const UnsupportedWarning(
          'provider-defined tool anthropic.text_editor_20250429',
        ),
      ]);
    });

    test('全部工具均被丢弃 → tools:null / toolChoice:null,warnings 保留', () {
      final result = prepare(
        tools: [
          const ProviderTool(
            id: 'anthropic.text_editor_20250429',
            name: 'str_replace_based_edit_tool',
            args: {},
          ),
        ],
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, hasLength(1));
    });
  });

  group('prepareAnthropicTools client tools — computer', () {
    // 报告 08 §3.1:三版 wire type 各异、name 恒为 'computer'、
    // display_width_px/display_height_px/display_number 缺席写键。
    test('computer_20241022 → wire 对象 + beta computer-use-2024-10-22', () {
      final result = prepare(
        tools: [
          computer_20241022(
            displayWidthPx: 1024,
            displayHeightPx: 768,
            displayNumber: 1,
          ),
        ],
      );

      expect(result.tools, [
        {
          'type': 'computer_20241022',
          'name': 'computer',
          'display_width_px': 1024,
          'display_height_px': 768,
          'display_number': 1,
        },
      ]);
      expect(result.betas, contains('computer-use-2024-10-22'));
    });

    test('computer_20241022 省略 displayNumber → 无 display_number 键', () {
      final result = prepare(
        tools: [
          computer_20241022(displayWidthPx: 1024, displayHeightPx: 768),
        ],
      );

      expect(
        result.tools!.single.containsKey('display_number'),
        isFalse,
      );
    });

    test('computer_20250124 → type 与 beta 正确', () {
      final result = prepare(
        tools: [
          computer_20250124(displayWidthPx: 1024, displayHeightPx: 768),
        ],
      );

      expect(result.tools!.single['type'], 'computer_20250124');
      expect(result.betas, contains('computer-use-2025-01-24'));
    });

    test(
        'computer_20251124(enableZoom:true) → type/beta 正确且含 '
        'enable_zoom', () {
      final result = prepare(
        tools: [
          computer_20251124(
            displayWidthPx: 1024,
            displayHeightPx: 768,
            enableZoom: true,
          ),
        ],
      );

      expect(result.tools!.single['type'], 'computer_20251124');
      expect(result.tools!.single['enable_zoom'], isTrue);
      expect(result.betas, contains('computer-use-2025-11-24'));
    });

    test('computer_20251124 省略 enableZoom → 无 enable_zoom 键', () {
      final result = prepare(
        tools: [
          computer_20251124(displayWidthPx: 1024, displayHeightPx: 768),
        ],
      );

      expect(
        result.tools!.single.containsKey('enable_zoom'),
        isFalse,
      );
    });

    test('非法 args 本地抛:displayWidthPx 类型错误', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.computer_20250124',
              name: 'computer',
              args: {'displayWidthPx': 'wide'},
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('prepareAnthropicTools client tools — text_editor', () {
    // 报告 08 §3.1(:217-220):20241022/20250124 wire name 恒为
    // str_replace_editor 且各自带 beta;20250728 wire name 为
    // str_replace_based_edit_tool、无 beta、可选 max_characters。
    test(
        'textEditor_20241022 → wire 对象 + beta '
        'computer-use-2024-10-22', () {
      final result = prepare(tools: [textEditor_20241022()]);

      expect(result.tools, [
        {'type': 'text_editor_20241022', 'name': 'str_replace_editor'},
      ]);
      expect(result.betas, contains('computer-use-2024-10-22'));
    });

    test(
        'textEditor_20250124 → wire 对象 + beta '
        'computer-use-2025-01-24', () {
      final result = prepare(tools: [textEditor_20250124()]);

      expect(result.tools, [
        {'type': 'text_editor_20250124', 'name': 'str_replace_editor'},
      ]);
      expect(result.betas, contains('computer-use-2025-01-24'));
    });

    test(
        'textEditor_20250728(maxCharacters) → wire 对象含 '
        'max_characters 且无 beta', () {
      final result = prepare(
        tools: [textEditor_20250728(maxCharacters: 5000)],
      );

      expect(result.tools, [
        {
          'type': 'text_editor_20250728',
          'name': 'str_replace_based_edit_tool',
          'max_characters': 5000,
        },
      ]);
      expect(
        result.betas.where((b) => b.startsWith('computer-use-')),
        isEmpty,
      );
    });

    test('textEditor_20250728 省略 maxCharacters → 无 max_characters 键', () {
      final result = prepare(tools: [textEditor_20250728()]);

      expect(
        result.tools!.single.containsKey('max_characters'),
        isFalse,
      );
    });

    test('非法 args 本地抛:maxCharacters 类型错误', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.text_editor_20250728',
              name: 'str_replace_based_edit_tool',
              args: {'maxCharacters': 'big'},
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('prepareAnthropicTools client tools — bash', () {
    // 报告 08 §3.1:两版 wire type 各异、name 恒为 'bash'、无 args。
    test('bash_20241022 → wire 对象 + beta computer-use-2024-10-22', () {
      final result = prepare(tools: [bash_20241022()]);

      expect(result.tools, [
        {'type': 'bash_20241022', 'name': 'bash'},
      ]);
      expect(result.betas, contains('computer-use-2024-10-22'));
    });

    test('bash_20250124 → wire 对象 + beta computer-use-2025-01-24', () {
      final result = prepare(tools: [bash_20250124()]);

      expect(result.tools, [
        {'type': 'bash_20250124', 'name': 'bash'},
      ]);
      expect(result.betas, contains('computer-use-2025-01-24'));
    });

    test('未知 provider id 行为不变:unsupported warning 并丢弃', () {
      // anthropic.memory_20250818 已被本批(batch 3)prepare_tools 分派支持,
      // 不再适合作为"未知 id"样本;改用 text_editor_20250429(deprecated
      // 版本,8 版决策 D3 排除,永远落入 default 分支),与本文件其余同类
      // "未知 id"测试(:592 一带)保持一致样本。
      final result = prepare(
        tools: [
          const ProviderTool(
            id: 'anthropic.text_editor_20250429',
            name: 'str_replace_based_edit_tool',
            args: {},
          ),
        ],
      );

      expect(result.tools, isNull);
      expect(result.warnings, [
        const UnsupportedWarning(
          'provider-defined tool anthropic.text_editor_20250429',
        ),
      ]);
    });
  });

  group('prepareAnthropicTools server tools — code_execution', () {
    // 报告 09 §2 表:20250522/20250825 各自带专属 beta,20260120 无 beta;
    // 三版 wire name 恒为 'code_execution'、均无 args、不写 cache_control 键
    // (20250522 上游写字面 cache_control: undefined,JSON 序列化即丢,报告
    // 09 §6.6——Dart 侧统一不写键,语义等价)。
    test(
        'codeExecution_20250522 → wire 对象 + beta '
        'code-execution-2025-05-22', () {
      final result = prepare(tools: [codeExecution_20250522()]);

      expect(result.tools, [
        {'type': 'code_execution_20250522', 'name': 'code_execution'},
      ]);
      expect(result.betas, contains('code-execution-2025-05-22'));
    });

    test(
        'codeExecution_20250825 → wire 对象 + beta '
        'code-execution-2025-08-25', () {
      final result = prepare(tools: [codeExecution_20250825()]);

      expect(result.tools, [
        {'type': 'code_execution_20250825', 'name': 'code_execution'},
      ]);
      expect(result.betas, contains('code-execution-2025-08-25'));
    });

    test('codeExecution_20260120 → wire 对象且 betas 为空集(无 beta)', () {
      // 报告 09 §7.2:上游 prepare-tools 测试快照 "betas": Set {}。
      final result = prepare(tools: [codeExecution_20260120()]);

      expect(result.tools, [
        {'type': 'code_execution_20260120', 'name': 'code_execution'},
      ]);
      expect(result.betas, isEmpty);
    });
  });

  group('prepareAnthropicTools server tools — memory', () {
    test(
        'memory_20250818 → wire 对象 + beta '
        'context-management-2025-06-27', () {
      final result = prepare(tools: [memory_20250818()]);

      expect(result.tools, [
        {'type': 'memory_20250818', 'name': 'memory'},
      ]);
      expect(result.betas, contains('context-management-2025-06-27'));
    });
  });

  group('prepareAnthropicTools server tools — tool_search', () {
    // 报告 09 §1.5/§1.6 警告:工厂 id 段无中间 tool,但 wire type/name 有;
    // 两版均无 beta。
    test('toolSearchRegex_20251119 → wire 对象含中间 tool 且无 beta', () {
      final result = prepare(tools: [toolSearchRegex_20251119()]);

      expect(result.tools, [
        {
          'type': 'tool_search_tool_regex_20251119',
          'name': 'tool_search_tool_regex',
        },
      ]);
      expect(result.betas, isEmpty);
    });

    test('toolSearchBm25_20251119 → wire 对象含中间 tool 且无 beta', () {
      final result = prepare(tools: [toolSearchBm25_20251119()]);

      expect(result.tools, [
        {
          'type': 'tool_search_tool_bm25_20251119',
          'name': 'tool_search_tool_bm25',
        },
      ]);
      expect(result.betas, isEmpty);
    });
  });

  group('prepareAnthropicTools server tools — advisor', () {
    // 报告 09 §7.2 anthropic-prepare-tools.test.ts 快照逐字对照
    // (model-only :934-967 / all-args :969-1007)。
    test('advisor_20260301(仅 model) → max_uses/caching 键缺席', () {
      final result = prepare(
        tools: [advisor_20260301(model: 'claude-opus-4-7')],
      );

      expect(result.tools, [
        {
          'type': 'advisor_20260301',
          'name': 'advisor',
          'model': 'claude-opus-4-7',
        },
      ]);
      expect(result.betas, {'advisor-tool-2026-03-01'});
    });

    test('advisor_20260301 全参 → max_uses/caching 键均写入', () {
      final result = prepare(
        tools: [
          advisor_20260301(
            model: 'claude-opus-4-7',
            maxUses: 5,
            caching: const AnthropicAdvisorCaching(ttl: '1h'),
          ),
        ],
      );

      expect(result.tools, [
        {
          'type': 'advisor_20260301',
          'name': 'advisor',
          'model': 'claude-opus-4-7',
          'max_uses': 5,
          'caching': {'type': 'ephemeral', 'ttl': '1h'},
        },
      ]);
    });

    test('非法 args 本地抛:model 缺失(唯一必填字段)', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.advisor_20260301',
              name: 'advisor',
              args: {},
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('非法 args 本地抛:maxUses 类型错误', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.advisor_20260301',
              name: 'advisor',
              args: {'model': 'claude-opus-4-7', 'maxUses': 'many'},
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('非法 args 本地抛:caching.ttl 越界(10m 不在 5m|1h)', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.advisor_20260301',
              name: 'advisor',
              args: {
                'model': 'claude-opus-4-7',
                'caching': {'type': 'ephemeral', 'ttl': '10m'},
              },
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('非法 args 本地抛:caching 缺必填 ttl', () {
      expect(
        () => prepare(
          tools: [
            const ProviderTool(
              id: 'anthropic.advisor_20260301',
              name: 'advisor',
              args: {
                'model': 'claude-opus-4-7',
                'caching': {'type': 'ephemeral'},
              },
            ),
          ],
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('prepareAnthropicTools server tools betas 并集(batch 3)', () {
    test('多个新工具混用时 betas 合并为单个 Set', () {
      final result = prepare(
        tools: [
          codeExecution_20250825(),
          memory_20250818(),
          advisor_20260301(model: 'claude-opus-4-7'),
        ],
      );

      expect(result.betas, {
        'code-execution-2025-08-25',
        'context-management-2025-06-27',
        'advisor-tool-2026-03-01',
      });
    });
  });
}
