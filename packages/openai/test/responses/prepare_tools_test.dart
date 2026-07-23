import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  // Compatibility fixture (unit): P1-OPENAI-06
  final weatherTool = FunctionTool(
    name: 'get_weather',
    description: 'Get the weather for a city',
    inputSchema: const JsonSchema({
      'type': 'object',
      'properties': {
        'city': {'type': 'string'},
      },
    }),
  );

  group('prepareOpenAiResponsesTools — tools array', () {
    test('null tools list yields no tools/toolChoice', () {
      final result = prepareOpenAiResponsesTools(
        tools: null,
        toolChoice: null,
      );
      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, isEmpty);
    });

    test('empty tools list yields no tools/toolChoice', () {
      final result = prepareOpenAiResponsesTools(tools: [], toolChoice: null);
      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
    });

    test('function tool maps to flat {type,name,description,parameters}', () {
      final result = prepareOpenAiResponsesTools(
        tools: [weatherTool],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'function',
          'name': 'get_weather',
          'description': 'Get the weather for a city',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        },
      ]);
    });

    test('description absent when not set (no key, not null)', () {
      final noDescriptionTool = FunctionTool(
        name: 'get_weather',
        inputSchema: const JsonSchema({'type': 'object'}),
      );
      final result = prepareOpenAiResponsesTools(
        tools: [noDescriptionTool],
        toolChoice: null,
      );
      expect(result.tools!.single.containsKey('description'), isFalse);
    });

    test('strict:true is included when set', () {
      final strictTool = FunctionTool(
        name: 'strict_tool',
        inputSchema: const JsonSchema({'type': 'object'}),
        strict: true,
      );
      final result = prepareOpenAiResponsesTools(
        tools: [strictTool],
        toolChoice: null,
      );

      expect(result.tools!.single['strict'], true);
    });

    test('strict absent when not set (no key, not null)', () {
      final result = prepareOpenAiResponsesTools(
        tools: [weatherTool],
        toolChoice: null,
      );
      expect(result.tools!.single.containsKey('strict'), isFalse);
    });

    test('openaiTools.webSearch creates an OpenAI web search ProviderTool', () {
      final tool = openAiTools.webSearch(
        externalWebAccess: false,
        filters: const OpenAiWebSearchFilters(
          allowedDomains: ['example.com'],
        ),
        searchContextSize: 'high',
        userLocation: const OpenAiWebSearchUserLocation(
          country: 'US',
          city: 'San Francisco',
          region: 'California',
          timezone: 'America/Los_Angeles',
        ),
      );

      expect(tool.id, 'openai.web_search');
      expect(tool.name, 'web_search');
      expect(tool.args, {
        'externalWebAccess': false,
        'filters': {
          'allowedDomains': ['example.com'],
        },
        'searchContextSize': 'high',
        'userLocation': {
          'type': 'approximate',
          'country': 'US',
          'city': 'San Francisco',
          'region': 'California',
          'timezone': 'America/Los_Angeles',
        },
      });
    });

    test('openaiTools.computer maps to the Responses computer tool', () {
      final tool = openAiTools.computer();
      final result = prepareOpenAiResponsesTools(
        tools: [tool],
        toolChoice: const ToolChoiceTool('computer'),
      );

      expect(
          tool,
          const ProviderTool(
            id: 'openai.computer',
            name: 'computer',
            args: {},
          ));
      expect(result.tools, [
        {'type': 'computer'},
      ]);
      expect(result.toolChoice, {'type': 'computer'});
      expect(result.warnings, isEmpty);
    });

    test('openai.web_search ProviderTool maps to Responses web_search', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          weatherTool,
          openAiTools.webSearch(
            externalWebAccess: false,
            filters: const OpenAiWebSearchFilters(
              allowedDomains: ['example.com'],
            ),
            searchContextSize: 'low',
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'function',
          'name': 'get_weather',
          'description': 'Get the weather for a city',
          'parameters': {
            'type': 'object',
            'properties': {
              'city': {'type': 'string'},
            },
          },
        },
        {
          'type': 'web_search',
          'external_web_access': false,
          'filters': {
            'allowed_domains': ['example.com'],
          },
          'search_context_size': 'low',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openaiTools.fileSearch creates an OpenAI file search ProviderTool',
        () {
      final tool = openAiTools.fileSearch(
        vectorStoreIds: ['vs_1'],
        maxNumResults: 3,
        ranking: const OpenAiFileSearchRanking(
          ranker: 'auto',
          scoreThreshold: 0.4,
        ),
        filters: const OpenAiFileSearchComparisonFilter(
          key: 'kind',
          type: 'eq',
          value: 'docs',
        ),
      );

      expect(tool.id, 'openai.file_search');
      expect(tool.name, 'file_search');
      expect(tool.args, {
        'vectorStoreIds': ['vs_1'],
        'maxNumResults': 3,
        'ranking': {
          'ranker': 'auto',
          'scoreThreshold': 0.4,
        },
        'filters': {
          'key': 'kind',
          'type': 'eq',
          'value': 'docs',
        },
      });
    });

    test('openai.file_search ProviderTool maps to Responses file_search', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.fileSearch(
            vectorStoreIds: ['vs_1'],
            maxNumResults: 3,
            ranking: const OpenAiFileSearchRanking(
              ranker: 'auto',
              scoreThreshold: 0.4,
            ),
            filters: const OpenAiFileSearchCompoundFilter(
              type: 'and',
              filters: [
                OpenAiFileSearchComparisonFilter(
                  key: 'kind',
                  type: 'eq',
                  value: 'docs',
                ),
              ],
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'file_search',
          'vector_store_ids': ['vs_1'],
          'max_num_results': 3,
          'ranking_options': {
            'ranker': 'auto',
            'score_threshold': 0.4,
          },
          'filters': {
            'type': 'and',
            'filters': [
              {
                'key': 'kind',
                'type': 'eq',
                'value': 'docs',
              },
            ],
          },
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.file_search accepts numeric set filter values', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.fileSearch(
            vectorStoreIds: ['vs_1'],
            filters: const OpenAiFileSearchComparisonFilter(
              key: 'year',
              type: 'in',
              value: [2024, 2025],
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'file_search',
          'vector_store_ids': ['vs_1'],
          'filters': {
            'key': 'year',
            'type': 'in',
            'value': [2024, 2025],
          },
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test(
        'openaiTools.codeInterpreter creates an OpenAI code interpreter '
        'ProviderTool', () {
      final tool = openAiTools.codeInterpreter(
        container: const OpenAiCodeInterpreterContainer(fileIds: ['file_1']),
      );

      expect(tool.id, 'openai.code_interpreter');
      expect(tool.name, 'code_interpreter');
      expect(tool.args, {
        'container': {
          'fileIds': ['file_1'],
        },
      });
    });

    test('openai.code_interpreter ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.codeInterpreter(
            container: const OpenAiCodeInterpreterContainer(
              fileIds: ['file_1'],
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'code_interpreter',
          'container': {
            'type': 'auto',
            'file_ids': ['file_1'],
          },
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.code_interpreter accepts an existing container id', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.codeInterpreter(
            container: const OpenAiCodeInterpreterContainer.id('cntr_1'),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'code_interpreter',
          'container': 'cntr_1',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test(
        'openaiTools.imageGeneration creates an OpenAI image generation '
        'ProviderTool', () {
      final tool = openAiTools.imageGeneration(
        action: 'generate',
        background: 'transparent',
        inputFidelity: 'high',
        inputImageMask: const OpenAiImageGenerationInputImageMask(
          fileId: 'file_mask',
          imageUrl: 'data:image/png;base64,mask',
        ),
        model: 'gpt-image-2',
        moderation: 'auto',
        outputCompression: 80,
        outputFormat: 'webp',
        partialImages: 2,
        quality: 'high',
        size: '1536x1024',
      );

      expect(tool.id, 'openai.image_generation');
      expect(tool.name, 'image_generation');
      expect(tool.args, {
        'action': 'generate',
        'background': 'transparent',
        'inputFidelity': 'high',
        'inputImageMask': {
          'fileId': 'file_mask',
          'imageUrl': 'data:image/png;base64,mask',
        },
        'model': 'gpt-image-2',
        'moderation': 'auto',
        'outputCompression': 80,
        'outputFormat': 'webp',
        'partialImages': 2,
        'quality': 'high',
        'size': '1536x1024',
      });
    });

    test('openai.image_generation ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.imageGeneration(
            action: 'edit',
            background: 'opaque',
            inputFidelity: 'low',
            inputImageMask: const OpenAiImageGenerationInputImageMask(
              fileId: 'file_mask',
              imageUrl: 'data:image/png;base64,mask',
            ),
            model: 'gpt-image-2',
            moderation: 'low',
            outputCompression: 80,
            outputFormat: 'jpeg',
            partialImages: 2,
            quality: 'medium',
            size: '2048x2048',
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'image_generation',
          'action': 'edit',
          'background': 'opaque',
          'input_fidelity': 'low',
          'input_image_mask': {
            'file_id': 'file_mask',
            'image_url': 'data:image/png;base64,mask',
          },
          'model': 'gpt-image-2',
          'moderation': 'low',
          'output_compression': 80,
          'output_format': 'jpeg',
          'partial_images': 2,
          'quality': 'medium',
          'size': '2048x2048',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.image_generation rejects unsupported action values', () {
      expect(
        () => prepareOpenAiResponsesTools(
          tools: [openAiTools.imageGeneration(action: 'create')],
          toolChoice: null,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('openaiTools.mcp creates an OpenAI MCP ProviderTool', () {
      final tool = openAiTools.mcp(
        serverLabel: 'dmcp',
        serverUrl: 'https://mcp.example.com',
        allowedTools: const OpenAiMcpAllowedTools.filter(
          readOnly: true,
          toolNames: ['search'],
        ),
        authorization: 'Bearer token',
        headers: const {'x-test': '1'},
        requireApproval:
            const OpenAiMcpRequireApproval.never(toolNames: ['search']),
        serverDescription: 'Demo MCP server',
      );

      expect(tool.id, 'openai.mcp');
      expect(tool.name, 'mcp');
      expect(tool.args, {
        'serverLabel': 'dmcp',
        'serverUrl': 'https://mcp.example.com',
        'allowedTools': {
          'readOnly': true,
          'toolNames': ['search'],
        },
        'authorization': 'Bearer token',
        'headers': {'x-test': '1'},
        'requireApproval': {
          'never': {
            'toolNames': ['search'],
          },
        },
        'serverDescription': 'Demo MCP server',
      });
    });

    test('openai.mcp ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
            allowedTools: const OpenAiMcpAllowedTools.filter(
              readOnly: true,
              toolNames: ['search'],
            ),
            authorization: 'Bearer token',
            headers: const {'x-test': '1'},
            requireApproval:
                const OpenAiMcpRequireApproval.never(toolNames: ['search']),
            serverDescription: 'Demo MCP server',
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'mcp',
          'server_label': 'dmcp',
          'allowed_tools': {
            'read_only': true,
            'tool_names': ['search'],
          },
          'authorization': 'Bearer token',
          'headers': {'x-test': '1'},
          'require_approval': {
            'never': {
              'tool_names': ['search'],
            },
          },
          'server_description': 'Demo MCP server',
          'server_url': 'https://mcp.example.com',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.mcp accepts a connector id and tool-name allowlist', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'connector',
            connectorId: 'conn_123',
            allowedTools: const OpenAiMcpAllowedTools.names(['search']),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'mcp',
          'server_label': 'connector',
          'allowed_tools': ['search'],
          'connector_id': 'conn_123',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.mcp accepts always approval filters', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
            requireApproval: const OpenAiMcpRequireApproval.always(
              readOnly: false,
              toolNames: ['delete'],
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'mcp',
          'server_label': 'dmcp',
          'require_approval': {
            'always': {
              'read_only': false,
              'tool_names': ['delete'],
            },
          },
          'server_url': 'https://mcp.example.com',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.mcp accepts combined approval filters', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
            requireApproval: const OpenAiMcpRequireApproval.filter(
              always: OpenAiMcpApprovalFilter(toolNames: ['delete']),
              never: OpenAiMcpApprovalFilter(readOnly: true),
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'mcp',
          'server_label': 'dmcp',
          'require_approval': {
            'always': {
              'tool_names': ['delete'],
            },
            'never': {
              'read_only': true,
            },
          },
          'server_url': 'https://mcp.example.com',
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.mcp requires serverUrl or connectorId', () {
      expect(
        () => prepareOpenAiResponsesTools(
          tools: [openAiTools.mcp(serverLabel: 'dmcp')],
          toolChoice: null,
        ),
        throwsA(isA<TypeValidationError>()),
      );
    });

    test('openaiTools.applyPatch creates an OpenAI apply patch ProviderTool',
        () {
      final tool = openAiTools.applyPatch();

      expect(tool.id, 'openai.apply_patch');
      expect(tool.name, 'apply_patch');
      expect(tool.args, isEmpty);
    });

    test('openai.apply_patch ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.applyPatch()],
        toolChoice: null,
      );

      expect(result.tools, [
        {'type': 'apply_patch'},
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openaiTools.toolSearch creates an OpenAI tool search ProviderTool',
        () {
      final tool = openAiTools.toolSearch(
        execution: 'client',
        description: 'Load tools by topic',
        parameters: const {
          'type': 'object',
          'properties': {
            'topic': {'type': 'string'},
          },
        },
      );

      expect(tool.id, 'openai.tool_search');
      expect(tool.name, 'tool_search');
      expect(tool.args, {
        'execution': 'client',
        'description': 'Load tools by topic',
        'parameters': {
          'type': 'object',
          'properties': {
            'topic': {'type': 'string'},
          },
        },
      });
    });

    test('openai.tool_search ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.toolSearch(
            execution: 'client',
            description: 'Load tools by topic',
            parameters: const {
              'type': 'object',
              'properties': {
                'topic': {'type': 'string'},
              },
            },
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'tool_search',
          'execution': 'client',
          'description': 'Load tools by topic',
          'parameters': {
            'type': 'object',
            'properties': {
              'topic': {'type': 'string'},
            },
          },
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openaiTools.customTool creates an OpenAI custom ProviderTool', () {
      final tool = openAiTools.customTool(
        name: 'grammar_out',
        description: 'Emit a constrained command',
        format: const OpenAiCustomToolFormat.grammar(
          syntax: 'lark',
          definition: 'start: /[a-z]+/',
        ),
      );

      expect(tool.id, 'openai.custom');
      expect(tool.name, 'grammar_out');
      expect(tool.args, {
        'description': 'Emit a constrained command',
        'format': {
          'type': 'grammar',
          'syntax': 'lark',
          'definition': 'start: /[a-z]+/',
        },
      });
    });

    test('openai.custom ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.customTool(
            name: 'grammar_out',
            description: 'Emit a constrained command',
            format: const OpenAiCustomToolFormat.text(),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'custom',
          'name': 'grammar_out',
          'description': 'Emit a constrained command',
          'format': {'type': 'text'},
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openaiTools.shell creates an OpenAI shell ProviderTool', () {
      final tool = openAiTools.shell(
        environment: const OpenAiShellEnvironmentContainerAuto(
          fileIds: ['file_1'],
          memoryLimit: '4g',
          networkPolicy: OpenAiShellNetworkPolicyAllowlist(
            allowedDomains: ['example.com'],
            domainSecrets: [
              OpenAiShellDomainSecret(
                domain: 'example.com',
                name: 'API_KEY',
                value: 'secret',
              ),
            ],
          ),
          skills: [
            OpenAiShellSkillReference(
              providerReference: {'openai': 'skill_1'},
              version: '2',
            ),
            OpenAiShellInlineSkill(
              name: 'demo',
              description: 'Demo skill',
              data: 'UEsDBA==',
            ),
          ],
        ),
      );

      expect(tool.id, 'openai.shell');
      expect(tool.name, 'shell');
      expect(tool.args, {
        'environment': {
          'type': 'containerAuto',
          'fileIds': ['file_1'],
          'memoryLimit': '4g',
          'networkPolicy': {
            'type': 'allowlist',
            'allowedDomains': ['example.com'],
            'domainSecrets': [
              {
                'domain': 'example.com',
                'name': 'API_KEY',
                'value': 'secret',
              },
            ],
          },
          'skills': [
            {
              'type': 'skillReference',
              'providerReference': {'openai': 'skill_1'},
              'version': '2',
            },
            {
              'type': 'inline',
              'name': 'demo',
              'description': 'Demo skill',
              'source': {
                'type': 'base64',
                'mediaType': 'application/zip',
                'data': 'UEsDBA==',
              },
            },
          ],
        },
      });
    });

    test('openai.shell containerAuto ProviderTool maps to Responses tool', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.shell(
            environment: const OpenAiShellEnvironmentContainerAuto(
              fileIds: ['file_1'],
              memoryLimit: '4g',
              networkPolicy: OpenAiShellNetworkPolicyAllowlist(
                allowedDomains: ['example.com'],
                domainSecrets: [
                  OpenAiShellDomainSecret(
                    domain: 'example.com',
                    name: 'API_KEY',
                    value: 'secret',
                  ),
                ],
              ),
              skills: [
                OpenAiShellSkillReference(
                  providerReference: {'openai': 'skill_1'},
                  version: '2',
                ),
                OpenAiShellInlineSkill(
                  name: 'demo',
                  description: 'Demo skill',
                  data: 'UEsDBA==',
                ),
              ],
            ),
          ),
        ],
        toolChoice: null,
      );

      expect(result.tools, [
        {
          'type': 'shell',
          'environment': {
            'type': 'container_auto',
            'file_ids': ['file_1'],
            'memory_limit': '4g',
            'network_policy': {
              'type': 'allowlist',
              'allowed_domains': ['example.com'],
              'domain_secrets': [
                {
                  'domain': 'example.com',
                  'name': 'API_KEY',
                  'value': 'secret',
                },
              ],
            },
            'skills': [
              {
                'type': 'skill_reference',
                'skill_id': 'skill_1',
                'version': '2',
              },
              {
                'type': 'inline',
                'name': 'demo',
                'description': 'Demo skill',
                'source': {
                  'type': 'base64',
                  'media_type': 'application/zip',
                  'data': 'UEsDBA==',
                },
              },
            ],
          },
        },
      ]);
      expect(result.warnings, isEmpty);
    });

    test('openai.shell local and containerReference environments map to wire',
        () {
      final localResult = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.shell(
            environment: const OpenAiShellEnvironmentLocal(
              skills: [
                OpenAiShellLocalSkill(
                  name: 'local-demo',
                  description: 'Local demo skill',
                  path: '/tmp/skill',
                ),
              ],
            ),
          ),
        ],
        toolChoice: null,
      );
      final referenceResult = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.shell(
            environment:
                const OpenAiShellEnvironmentContainerReference('cntr_1'),
          ),
        ],
        toolChoice: null,
      );

      expect(localResult.tools, [
        {
          'type': 'shell',
          'environment': {
            'type': 'local',
            'skills': [
              {
                'name': 'local-demo',
                'description': 'Local demo skill',
                'path': '/tmp/skill',
              },
            ],
          },
        },
      ]);
      expect(referenceResult.tools, [
        {
          'type': 'shell',
          'environment': {
            'type': 'container_reference',
            'container_id': 'cntr_1',
          },
        },
      ]);
    });

    test(
        'all-unknown ProviderTool list yields no tools/toolChoice '
        '(graceful downgrade)', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          const ProviderTool(
            id: 'openai.unknown',
            name: 'unknown',
            args: {},
          ),
        ],
        toolChoice: const ToolChoiceAuto(),
      );

      expect(result.tools, isNull);
      expect(result.toolChoice, isNull);
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
    });
  });

  group('prepareOpenAiResponsesTools — toolChoice', () {
    test('auto/none/required pass through as bare strings', () {
      for (final MapEntry(key: choice, value: expected) in {
        const ToolChoiceAuto(): 'auto',
        const ToolChoiceNone(): 'none',
        const ToolChoiceRequired(): 'required',
      }.entries) {
        final result = prepareOpenAiResponsesTools(
          tools: [weatherTool],
          toolChoice: choice,
        );
        expect(result.toolChoice, expected);
      }
    });

    test('tool choice for a plain function maps to {type,name}', () {
      final result = prepareOpenAiResponsesTools(
        tools: [weatherTool],
        toolChoice: const ToolChoiceTool('get_weather'),
      );
      expect(result.toolChoice, {'type': 'function', 'name': 'get_weather'});
    });

    test('tool choice for a web_search function stays a function', () {
      final webSearchFunction = FunctionTool(
        name: 'web_search',
        inputSchema: const JsonSchema({'type': 'object'}),
      );
      final result = prepareOpenAiResponsesTools(
        tools: [webSearchFunction],
        toolChoice: const ToolChoiceTool('web_search'),
      );

      expect(result.toolChoice, {'type': 'function', 'name': 'web_search'});
      expect(result.warnings, isEmpty);
    });

    test('web_search function choice wins over provider tool with same name',
        () {
      final webSearchFunction = FunctionTool(
        name: 'web_search',
        inputSchema: const JsonSchema({'type': 'object'}),
      );
      final result = prepareOpenAiResponsesTools(
        tools: [webSearchFunction, openAiTools.webSearch()],
        toolChoice: const ToolChoiceTool('web_search'),
      );

      expect(result.toolChoice, {'type': 'function', 'name': 'web_search'});
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming web_search maps to built-in tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.webSearch()],
        toolChoice: const ToolChoiceTool('web_search'),
      );
      expect(
        result.toolChoice,
        {'type': 'web_search'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming file_search maps to built-in tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.fileSearch(vectorStoreIds: ['vs_1'])
        ],
        toolChoice: const ToolChoiceTool('file_search'),
      );
      expect(
        result.toolChoice,
        {'type': 'file_search'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming code_interpreter maps to built-in tool choice',
        () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.codeInterpreter()],
        toolChoice: const ToolChoiceTool('code_interpreter'),
      );
      expect(
        result.toolChoice,
        {'type': 'code_interpreter'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming image_generation maps to built-in tool choice',
        () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.imageGeneration()],
        toolChoice: const ToolChoiceTool('image_generation'),
      );
      expect(
        result.toolChoice,
        {'type': 'image_generation'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming mcp maps to server-specific tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
          ),
        ],
        toolChoice: const ToolChoiceTool('mcp'),
      );
      expect(
        result.toolChoice,
        {'type': 'mcp', 'server_label': 'dmcp'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming an mcp subtool maps to MCP tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [
          openAiTools.mcp(
            serverLabel: 'dmcp',
            serverUrl: 'https://mcp.example.com',
            allowedTools: const OpenAiMcpAllowedTools.names(['search']),
          ),
        ],
        toolChoice: const ToolChoiceTool('mcp.search'),
      );
      expect(
        result.toolChoice,
        {'type': 'mcp', 'server_label': 'dmcp', 'name': 'search'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming apply_patch maps to built-in tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.applyPatch()],
        toolChoice: const ToolChoiceTool('apply_patch'),
      );
      expect(
        result.toolChoice,
        {'type': 'apply_patch'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming tool_search maps to built-in tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.toolSearch()],
        toolChoice: const ToolChoiceTool('tool_search'),
      );
      expect(
        result.toolChoice,
        {'type': 'tool_search'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming shell maps to built-in tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.shell()],
        toolChoice: const ToolChoiceTool('shell'),
      );
      expect(
        result.toolChoice,
        {'type': 'shell'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming custom tool maps to custom tool choice', () {
      final result = prepareOpenAiResponsesTools(
        tools: [openAiTools.customTool(name: 'grammar_out')],
        toolChoice: const ToolChoiceTool('grammar_out'),
      );
      expect(
        result.toolChoice,
        {'type': 'custom', 'name': 'grammar_out'},
      );
      expect(result.warnings, isEmpty);
    });

    test('tool choice for a file_search function stays a function', () {
      final fileSearchFunction = FunctionTool(
        name: 'file_search',
        inputSchema: const JsonSchema({'type': 'object'}),
      );
      final result = prepareOpenAiResponsesTools(
        tools: [
          fileSearchFunction,
          openAiTools.fileSearch(vectorStoreIds: ['vs_1']),
        ],
        toolChoice: const ToolChoiceTool('file_search'),
      );

      expect(result.toolChoice, {'type': 'function', 'name': 'file_search'});
      expect(result.warnings, isEmpty);
    });

    test('tool choice naming an unsupported built-in still degrades', () {
      final result = prepareOpenAiResponsesTools(
        tools: [weatherTool],
        toolChoice: const ToolChoiceTool('web_search_preview'),
      );
      expect(
        result.toolChoice,
        {'type': 'function', 'name': 'web_search_preview'},
      );
      expect(result.warnings, hasLength(1));
      expect(result.warnings.single, isA<UnsupportedWarning>());
    });
  });
}
