import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('AnthropicMessagesProviderOptions.fromProviderOptions — 字段表', () {
    test('null options 时返回全字段默认(null)的实例', () {
      final options = AnthropicMessagesProviderOptions.fromProviderOptions(
        null,
      );

      expect(options.sendReasoning, isNull);
      expect(options.structuredOutputMode, isNull);
      expect(options.thinking, isNull);
      expect(options.disableParallelToolUse, isNull);
      expect(options.cacheControl, isNull);
      expect(options.metadata, isNull);
      expect(options.toolStreaming, isNull);
      expect(options.effort, isNull);
      expect(options.inferenceGeo, isNull);
      expect(options.anthropicBeta, isNull);
    });

    test('anthropic 键为全空 map 时同样返回全字段默认', () {
      final options = AnthropicMessagesProviderOptions.fromProviderOptions(
        <String, JsonObject>{'anthropic': <String, Object?>{}},
      );

      expect(options.sendReasoning, isNull);
      expect(options.structuredOutputMode, isNull);
      expect(options.thinking, isNull);
      expect(options.disableParallelToolUse, isNull);
      expect(options.cacheControl, isNull);
      expect(options.metadata, isNull);
      expect(options.toolStreaming, isNull);
      expect(options.effort, isNull);
      expect(options.inferenceGeo, isNull);
      expect(options.anthropicBeta, isNull);
    });

    test('缺少 anthropic 键(仅其他键)时返回全字段默认', () {
      final options = AnthropicMessagesProviderOptions.fromProviderOptions(
        <String, JsonObject>{'openai': <String, Object?>{}},
      );

      expect(options.effort, isNull);
    });

    test('校验通过时逐字段读取', () {
      final options = AnthropicMessagesProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'anthropic': <String, Object?>{
            'sendReasoning': false,
            'structuredOutputMode': 'jsonTool',
            'thinking': <String, Object?>{
              'type': 'enabled',
              'budgetTokens': 2048,
            },
            'disableParallelToolUse': true,
            'cacheControl': <String, Object?>{
              'type': 'ephemeral',
              'ttl': '1h',
            },
            'metadata': <String, Object?>{'userId': 'user-123'},
            'toolStreaming': false,
            'effort': 'xhigh',
            'inferenceGeo': 'us',
            'anthropicBeta': <Object?>['beta-a', 'beta-b'],
          },
        },
      );

      expect(options.sendReasoning, false);
      expect(options.structuredOutputMode, 'jsonTool');
      expect(
        options.thinking,
        const AnthropicThinkingEnabled(budgetTokens: 2048),
      );
      expect(options.disableParallelToolUse, true);
      expect(
        options.cacheControl,
        <String, Object?>{'type': 'ephemeral', 'ttl': '1h'},
      );
      expect(options.metadata, <String, Object?>{'userId': 'user-123'});
      expect(options.toolStreaming, false);
      expect(options.effort, 'xhigh');
      expect(options.inferenceGeo, 'us');
      expect(options.anthropicBeta, <String>['beta-a', 'beta-b']);
    });

    test('structuredOutputMode 三取值均合法', () {
      for (final mode in <String>['outputFormat', 'jsonTool', 'auto']) {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'structuredOutputMode': mode},
          },
        );
        expect(options.structuredOutputMode, mode);
      }
    });

    test('effort 五取值均合法', () {
      for (final effort in <String>['low', 'medium', 'high', 'xhigh', 'max']) {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'effort': effort},
          },
        );
        expect(options.effort, effort);
      }
    });

    test('inferenceGeo 两取值均合法', () {
      for (final geo in <String>['us', 'global']) {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'inferenceGeo': geo},
          },
        );
        expect(options.inferenceGeo, geo);
      }
    });

    test('cacheControl 可省略 ttl', () {
      final options = AnthropicMessagesProviderOptions.fromProviderOptions(
        <String, JsonObject>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{'type': 'ephemeral'},
          },
        },
      );

      expect(options.cacheControl, <String, Object?>{'type': 'ephemeral'});
    });

    group('thinking 判别联合', () {
      test('enabled 可省略 budgetTokens', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'thinking': <String, Object?>{'type': 'enabled'},
            },
          },
        );

        expect(options.thinking, const AnthropicThinkingEnabled());
        expect(
          (options.thinking! as AnthropicThinkingEnabled).budgetTokens,
          isNull,
        );
      });

      test('adaptive 带 display', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'thinking': <String, Object?>{
                'type': 'adaptive',
                'display': 'summarized',
              },
            },
          },
        );

        expect(
          options.thinking,
          const AnthropicThinkingAdaptive(display: 'summarized'),
        );
      });

      test('adaptive 可省略 display', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'thinking': <String, Object?>{'type': 'adaptive'},
            },
          },
        );

        expect(options.thinking, const AnthropicThinkingAdaptive());
        expect(
          (options.thinking! as AnthropicThinkingAdaptive).display,
          isNull,
        );
      });

      test('disabled', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'thinking': <String, Object?>{'type': 'disabled'},
            },
          },
        );

        expect(options.thinking, const AnthropicThinkingDisabled());
      });

      test('type 非法时抛 TypeValidationError', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'thinking': <String, Object?>{'type': 'bogus'},
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });

      test('adaptive 的 display 非枚举值时抛 TypeValidationError', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'thinking': <String, Object?>{
                  'type': 'adaptive',
                  'display': 'verbose',
                },
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    test('effort 非枚举值时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'effort': 'huge'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('structuredOutputMode 非枚举值时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'structuredOutputMode': 'bogus'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('inferenceGeo 非枚举值时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'inferenceGeo': 'eu'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('sendReasoning 非 bool 时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{'sendReasoning': 'yes'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('cacheControl.ttl 非枚举值时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'cacheControl': <String, Object?>{
                'type': 'ephemeral',
                'ttl': '2h',
              },
            },
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('metadata.userId 非 string 时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'metadata': <String, Object?>{'userId': 1},
            },
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('anthropicBeta 元素非 string 时抛 TypeValidationError', () {
      expect(
        () => AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'anthropicBeta': <Object?>[1, 2],
            },
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('equatable 值相等', () {
      const a = AnthropicMessagesProviderOptions(
        effort: 'low',
        thinking: AnthropicThinkingEnabled(budgetTokens: 1024),
      );
      const b = AnthropicMessagesProviderOptions(
        effort: 'low',
        thinking: AnthropicThinkingEnabled(budgetTokens: 1024),
      );
      const c = AnthropicMessagesProviderOptions(
        effort: 'low',
        thinking: AnthropicThinkingEnabled(budgetTokens: 2048),
      );

      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });

  group('resolveAnthropicProviderOptions — 双 key 合并', () {
    test('providerOptions 为 null 时返回全默认 + usedCustomProviderKey=false', () {
      final resolved = resolveAnthropicProviderOptions(
        'anthropic.messages',
        null,
      );

      expect(resolved.options, const AnthropicMessagesProviderOptions());
      expect(resolved.usedCustomProviderKey, isFalse);
    });

    test('派生 key == anthropic 时只读 canonical', () {
      final resolved = resolveAnthropicProviderOptions(
        'anthropic.messages',
        <String, JsonObject>{
          'anthropic': <String, Object?>{'effort': 'low'},
        },
      );

      expect(resolved.options.effort, 'low');
      expect(resolved.usedCustomProviderKey, isFalse);
    });

    test('派生 key == anthropic 时不按自定义 key 二次解析(非法值不抛)', () {
      // providerName 派生 key 即 canonical,其他 key 下的内容不应被读取,
      // 即便其形状非法也不触发校验。
      final resolved = resolveAnthropicProviderOptions(
        'anthropic.messages',
        <String, JsonObject>{
          'anthropic': <String, Object?>{'effort': 'low'},
          'anthropic.messages': <String, Object?>{'effort': 'bogus'},
        },
      );

      expect(resolved.options.effort, 'low');
      expect(resolved.usedCustomProviderKey, isFalse);
    });

    test('字段级合并且自定义 key 覆盖 canonical', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-anthropic',
        <String, JsonObject>{
          'anthropic': <String, Object?>{
            'effort': 'low',
            'sendReasoning': false,
          },
          'my-anthropic': <String, Object?>{'effort': 'high'},
        },
      );

      expect(resolved.options.effort, 'high');
      expect(resolved.options.sendReasoning, false);
      expect(resolved.usedCustomProviderKey, isTrue);
    });

    test('派生 key 取完整 provider 串首个 . 之前的部分', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-custom-anthropic.messages',
        <String, JsonObject>{
          'my-custom-anthropic': <String, Object?>{'effort': 'medium'},
        },
      );

      expect(resolved.options.effort, 'medium');
      expect(resolved.usedCustomProviderKey, isTrue);
    });

    test('自定义 key 无值时 usedCustomProviderKey=false 且仅取 canonical', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-anthropic',
        <String, JsonObject>{
          'anthropic': <String, Object?>{'effort': 'low'},
        },
      );

      expect(resolved.options.effort, 'low');
      expect(resolved.usedCustomProviderKey, isFalse);
    });

    test('仅自定义 key 有值时 canonical 侧为全默认', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-anthropic',
        <String, JsonObject>{
          'my-anthropic': <String, Object?>{'toolStreaming': false},
        },
      );

      expect(resolved.options.toolStreaming, false);
      expect(resolved.options.effort, isNull);
      expect(resolved.usedCustomProviderKey, isTrue);
    });

    test('thinking 等复合字段同样按字段级整体覆盖', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-anthropic',
        <String, JsonObject>{
          'anthropic': <String, Object?>{
            'thinking': <String, Object?>{
              'type': 'enabled',
              'budgetTokens': 1024,
            },
            'metadata': <String, Object?>{'userId': 'u-1'},
          },
          'my-anthropic': <String, Object?>{
            'thinking': <String, Object?>{'type': 'disabled'},
          },
        },
      );

      expect(resolved.options.thinking, const AnthropicThinkingDisabled());
      expect(resolved.options.metadata, <String, Object?>{'userId': 'u-1'});
      expect(resolved.usedCustomProviderKey, isTrue);
    });

    test('自定义 key 下形状非法时抛 TypeValidationError', () {
      expect(
        () => resolveAnthropicProviderOptions(
          'my-anthropic',
          <String, JsonObject>{
            'my-anthropic': <String, Object?>{'effort': 'huge'},
          },
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });
  });

  group('beta 选项族六字段 parse(T8)', () {
    group('mcpServers', () {
      test('全键正向解析(含嵌套 toolConfiguration)', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'mcpServers': <Object?>[
                <String, Object?>{
                  'type': 'url',
                  'name': 'echo',
                  'url': 'https://mcp.example.com',
                  'authorizationToken': 'token-1',
                  'toolConfiguration': <String, Object?>{
                    'enabled': true,
                    'allowedTools': <Object?>['echo_tool'],
                  },
                },
                <String, Object?>{
                  'type': 'url',
                  'name': 'minimal',
                  'url': 'https://mcp2.example.com',
                },
              ],
            },
          },
        );

        expect(options.mcpServers, hasLength(2));
        expect(
          options.mcpServers![0],
          const AnthropicMcpServer(
            name: 'echo',
            url: 'https://mcp.example.com',
            authorizationToken: 'token-1',
            toolConfiguration: AnthropicMcpToolConfiguration(
              enabled: true,
              allowedTools: ['echo_tool'],
            ),
          ),
        );
        expect(
          options.mcpServers![1],
          const AnthropicMcpServer(
            name: 'minimal',
            url: 'https://mcp2.example.com',
          ),
        );
      });

      test('缺 url 时抛 TypeValidationError', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'mcpServers': <Object?>[
                  <String, Object?>{'type': 'url', 'name': 'echo'},
                ],
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    group('container', () {
      test('id + anthropic/custom 两型 skill 正向解析', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'container': <String, Object?>{
                'id': 'container_abc',
                'skills': <Object?>[
                  <String, Object?>{
                    'type': 'anthropic',
                    'skillId': 'pptx',
                    'version': 'latest',
                  },
                  <String, Object?>{
                    'type': 'custom',
                    'providerReference': <String, Object?>{
                      'anthropic': 'skill_01X',
                    },
                  },
                ],
              },
            },
          },
        );

        final container = options.container!;
        expect(container.id, 'container_abc');
        expect(container.skills, hasLength(2));
        expect(
          container.skills![0],
          const AnthropicAnthropicSkill(skillId: 'pptx', version: 'latest'),
        );
        expect(
          container.skills![1],
          const AnthropicCustomSkill(
            providerReference: {'anthropic': 'skill_01X'},
          ),
        );
      });

      test('空对象 container 合法(两字段均缺省)', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'container': <String, Object?>{},
            },
          },
        );

        expect(options.container, const AnthropicContainer());
      });

      test('未知 skill type 拒错', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'container': <String, Object?>{
                  'skills': <Object?>[
                    <String, Object?>{'type': 'bogus', 'skillId': 'x'},
                  ],
                },
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    group('taskBudget', () {
      test('total: 20000 缺省 remaining 过(下界合法)', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'taskBudget': <String, Object?>{
                'type': 'tokens',
                'total': 20000,
              },
            },
          },
        );

        expect(options.taskBudget, const AnthropicTaskBudget(total: 20000));
        expect(options.taskBudget!.remaining, isNull);
      });

      test('remaining: 0 合法(下界)', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'taskBudget': <String, Object?>{
                'type': 'tokens',
                'total': 30000,
                'remaining': 0,
              },
            },
          },
        );

        expect(
          options.taskBudget,
          const AnthropicTaskBudget(total: 30000, remaining: 0),
        );
      });

      test('total: 19999 拒(minimum 20000)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'taskBudget': <String, Object?>{
                  'type': 'tokens',
                  'total': 19999,
                },
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });

      test('remaining: -1 拒(minimum 0)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'taskBudget': <String, Object?>{
                  'type': 'tokens',
                  'total': 20000,
                  'remaining': -1,
                },
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });

      test('缺 type 拒(wire 字面量必填)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'taskBudget': <String, Object?>{'total': 20000},
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });

      test('整值 double 形态(JSON 反序列化路径)接受并转 int', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'taskBudget': <String, Object?>{
                'type': 'tokens',
                'total': 20000.0,
                'remaining': 5000.0,
              },
            },
          },
        );

        expect(
          options.taskBudget,
          const AnthropicTaskBudget(total: 20000, remaining: 5000),
        );
      });
    });

    group('speed', () {
      test("'fast' / 'standard' 均合法", () {
        for (final speed in <String>['fast', 'standard']) {
          final options = AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{'speed': speed},
            },
          );
          expect(options.speed, speed);
        }
      });

      test('非枚举值拒错', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{'speed': 'turbo'},
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    group('fallbacks', () {
      test('raw wire 形态原样保留(snake 键)', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'fallbacks': <Object?>[
                <String, Object?>{
                  'model': 'claude-opus-4-6',
                  'max_tokens': 2048,
                  'thinking': <String, Object?>{'type': 'disabled'},
                  'output_config': <String, Object?>{'effort': 'low'},
                  'speed': 'fast',
                },
              ],
            },
          },
        );

        expect(options.fallbacks, [
          <String, Object?>{
            'model': 'claude-opus-4-6',
            'max_tokens': 2048,
            'thinking': <String, Object?>{'type': 'disabled'},
            'output_config': <String, Object?>{'effort': 'low'},
            'speed': 'fast',
          },
        ]);
      });

      test('缺 model 拒错(条目内唯一必填键)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'fallbacks': <Object?>[
                  <String, Object?>{'max_tokens': 2048},
                ],
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    group('contextManagement', () {
      test('三 edit 型正向解析为判别联合', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'contextManagement': <String, Object?>{
                'edits': <Object?>[
                  <String, Object?>{
                    'type': 'clear_tool_uses_20250919',
                    'trigger': <String, Object?>{
                      'type': 'tool_uses',
                      'value': 5,
                    },
                    'keep': <String, Object?>{
                      'type': 'tool_uses',
                      'value': 2,
                    },
                    'clearAtLeast': <String, Object?>{
                      'type': 'input_tokens',
                      'value': 1000,
                    },
                    'clearToolInputs': false,
                    'excludeTools': <Object?>['web_search'],
                  },
                  <String, Object?>{
                    'type': 'clear_thinking_20251015',
                    'keep': 'all',
                  },
                  <String, Object?>{
                    'type': 'compact_20260112',
                    'trigger': <String, Object?>{
                      'type': 'input_tokens',
                      'value': 100000,
                    },
                    'pauseAfterCompaction': true,
                    'instructions': 'be brief',
                  },
                ],
              },
            },
          },
        );

        final edits = options.contextManagement!.edits;
        expect(edits, hasLength(3));
        expect(
          edits[0],
          const AnthropicClearToolUses20250919Edit(
            trigger: {'type': 'tool_uses', 'value': 5},
            keep: {'type': 'tool_uses', 'value': 2},
            clearAtLeast: {'type': 'input_tokens', 'value': 1000},
            clearToolInputs: false,
            excludeTools: ['web_search'],
          ),
        );
        expect(edits[1], const AnthropicClearThinking20251015Edit(keep: 'all'));
        expect(
          edits[2],
          const AnthropicCompact20260112Edit(
            trigger: {'type': 'input_tokens', 'value': 100000},
            pauseAfterCompaction: true,
            instructions: 'be brief',
          ),
        );
      });

      test('clear_thinking keep 支持对象形态', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'contextManagement': <String, Object?>{
                'edits': <Object?>[
                  <String, Object?>{
                    'type': 'clear_thinking_20251015',
                    'keep': <String, Object?>{
                      'type': 'thinking_turns',
                      'value': 3,
                    },
                  },
                ],
              },
            },
          },
        );

        expect(
          options.contextManagement!.edits.single,
          const AnthropicClearThinking20251015Edit(
            keep: {'type': 'thinking_turns', 'value': 3},
          ),
        );
      });

      test('空 edits 合法并保留为空列表', () {
        final options = AnthropicMessagesProviderOptions.fromProviderOptions(
          <String, JsonObject>{
            'anthropic': <String, Object?>{
              'contextManagement': <String, Object?>{'edits': <Object?>[]},
            },
          },
        );

        expect(
          options.contextManagement,
          const AnthropicContextManagement(edits: []),
        );
      });

      test('未知 edit type 拒错(上游 discriminatedUnion 在 parse 阶段即抛)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'contextManagement': <String, Object?>{
                  'edits': <Object?>[
                    <String, Object?>{'type': 'clear_everything_20990101'},
                  ],
                },
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });

      test('缺 edits 键拒错(edits 必填)', () {
        expect(
          () => AnthropicMessagesProviderOptions.fromProviderOptions(
            <String, JsonObject>{
              'anthropic': <String, Object?>{
                'contextManagement': <String, Object?>{},
              },
            },
          ),
          throwsA(isA<TypeValidationError>()),
        );
      });
    });

    test('六新字段进 props(equality 回归)', () {
      const a = AnthropicMessagesProviderOptions(
        taskBudget: AnthropicTaskBudget(total: 20000),
        speed: 'fast',
      );
      const b = AnthropicMessagesProviderOptions(
        taskBudget: AnthropicTaskBudget(total: 20000),
        speed: 'fast',
      );
      const c = AnthropicMessagesProviderOptions(
        taskBudget: AnthropicTaskBudget(total: 20000, remaining: 1),
        speed: 'fast',
      );
      const d = AnthropicMessagesProviderOptions(
        taskBudget: AnthropicTaskBudget(total: 20000),
        speed: 'standard',
      );

      expect(a, equals(b));
      expect(a == c, isFalse);
      expect(a == d, isFalse);
      expect(
        const AnthropicMessagesProviderOptions(
          container: AnthropicContainer(id: 'c1'),
        ),
        isNot(
          equals(
            const AnthropicMessagesProviderOptions(
              container: AnthropicContainer(id: 'c2'),
            ),
          ),
        ),
      );
    });
  });

  group('resolveAnthropicProviderOptions — 六新字段双 key 合并(T8)', () {
    test('自定义 key 字段级覆盖,未覆盖字段保 canonical', () {
      final resolved = resolveAnthropicProviderOptions(
        'my-anthropic',
        <String, JsonObject>{
          'anthropic': <String, Object?>{
            'taskBudget': <String, Object?>{'type': 'tokens', 'total': 20000},
            'speed': 'standard',
            'mcpServers': <Object?>[
              <String, Object?>{
                'type': 'url',
                'name': 'echo',
                'url': 'https://mcp.example.com',
              },
            ],
          },
          'my-anthropic': <String, Object?>{
            'speed': 'fast',
            'container': <String, Object?>{'id': 'c1'},
          },
        },
      );

      expect(
        resolved.options.taskBudget,
        const AnthropicTaskBudget(total: 20000),
      );
      expect(resolved.options.speed, 'fast');
      expect(resolved.options.container, const AnthropicContainer(id: 'c1'));
      expect(resolved.options.mcpServers, hasLength(1));
      expect(resolved.usedCustomProviderKey, isTrue);
    });
  });
}
