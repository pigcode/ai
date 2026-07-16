import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// 命中暂未支持内置工具类型名的 `ToolChoiceTool.toolName` 集合(仅用于降级判定)。
const _unsupportedBuiltInToolChoiceNames = <String>{
  'web_search_preview',
};

final _customArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'description': {'type': 'string'},
      'format': {
        'oneOf': [
          {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['grammar'],
              },
              'syntax': {
                'type': 'string',
                'enum': ['regex', 'lark'],
              },
              'definition': {'type': 'string'},
            },
            'required': ['type', 'syntax', 'definition'],
            'additionalProperties': false,
          },
          {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['text'],
              },
            },
            'required': ['type'],
            'additionalProperties': false,
          },
        ],
      },
    },
    'additionalProperties': false,
  }),
);

final _mcpArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'serverLabel': {'type': 'string'},
      'allowedTools': {
        'oneOf': [
          {
            'type': 'array',
            'items': {'type': 'string'},
          },
          {
            'type': 'object',
            'properties': {
              'readOnly': {'type': 'boolean'},
              'toolNames': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'additionalProperties': false,
          },
        ],
      },
      'authorization': {'type': 'string'},
      'connectorId': {'type': 'string'},
      'headers': {
        'type': 'object',
        'additionalProperties': {'type': 'string'},
      },
      'requireApproval': {
        'oneOf': [
          {
            'type': 'string',
            'enum': ['always', 'never'],
          },
          {
            'type': 'object',
            'properties': {
              'always': {
                'type': 'object',
                'properties': {
                  'readOnly': {'type': 'boolean'},
                  'toolNames': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'additionalProperties': false,
              },
              'never': {
                'type': 'object',
                'properties': {
                  'readOnly': {'type': 'boolean'},
                  'toolNames': {
                    'type': 'array',
                    'items': {'type': 'string'},
                  },
                },
                'additionalProperties': false,
              },
            },
            'additionalProperties': false,
          },
        ],
      },
      'serverDescription': {'type': 'string'},
      'serverUrl': {'type': 'string'},
    },
    'required': ['serverLabel'],
    'additionalProperties': false,
  }),
);

final _imageGenerationArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'action': {
        'type': 'string',
        'enum': ['auto', 'generate', 'edit'],
      },
      'background': {
        'type': 'string',
        'enum': ['auto', 'opaque', 'transparent'],
      },
      'inputFidelity': {
        'type': 'string',
        'enum': ['low', 'high'],
      },
      'inputImageMask': {
        'type': 'object',
        'properties': {
          'fileId': {'type': 'string'},
          'imageUrl': {'type': 'string'},
        },
        'additionalProperties': false,
      },
      'model': {'type': 'string'},
      'moderation': {
        'type': 'string',
        'enum': ['auto', 'low'],
      },
      'outputCompression': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 100,
      },
      'outputFormat': {
        'type': 'string',
        'enum': ['png', 'jpeg', 'webp'],
      },
      'partialImages': {
        'type': 'integer',
        'minimum': 0,
        'maximum': 3,
      },
      'quality': {
        'type': 'string',
        'enum': ['auto', 'low', 'medium', 'high'],
      },
      'size': {'type': 'string'},
    },
    'additionalProperties': false,
  }),
);

final _shellArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'environment': {
        'oneOf': [
          {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['containerAuto'],
              },
              'fileIds': {
                'type': 'array',
                'items': {'type': 'string'},
              },
              'memoryLimit': {
                'type': 'string',
                'enum': ['1g', '4g', '16g', '64g'],
              },
              'networkPolicy': {
                'oneOf': [
                  {
                    'type': 'object',
                    'properties': {
                      'type': {
                        'type': 'string',
                        'enum': ['disabled'],
                      },
                    },
                    'required': ['type'],
                    'additionalProperties': false,
                  },
                  {
                    'type': 'object',
                    'properties': {
                      'type': {
                        'type': 'string',
                        'enum': ['allowlist'],
                      },
                      'allowedDomains': {
                        'type': 'array',
                        'items': {'type': 'string'},
                      },
                      'domainSecrets': {
                        'type': 'array',
                        'items': {
                          'type': 'object',
                          'properties': {
                            'domain': {'type': 'string'},
                            'name': {'type': 'string'},
                            'value': {'type': 'string'},
                          },
                          'required': ['domain', 'name', 'value'],
                          'additionalProperties': false,
                        },
                      },
                    },
                    'required': ['type', 'allowedDomains'],
                    'additionalProperties': false,
                  },
                ],
              },
              'skills': {
                'type': 'array',
                'items': {
                  'oneOf': [
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['skillReference'],
                        },
                        'providerReference': {
                          'type': 'object',
                          'additionalProperties': {'type': 'string'},
                        },
                        'version': {'type': 'string'},
                      },
                      'required': ['type', 'providerReference'],
                      'additionalProperties': false,
                    },
                    {
                      'type': 'object',
                      'properties': {
                        'type': {
                          'type': 'string',
                          'enum': ['inline'],
                        },
                        'name': {'type': 'string'},
                        'description': {'type': 'string'},
                        'source': {
                          'type': 'object',
                          'properties': {
                            'type': {
                              'type': 'string',
                              'enum': ['base64'],
                            },
                            'mediaType': {
                              'type': 'string',
                              'enum': ['application/zip'],
                            },
                            'data': {'type': 'string'},
                          },
                          'required': ['type', 'mediaType', 'data'],
                          'additionalProperties': false,
                        },
                      },
                      'required': ['type', 'name', 'description', 'source'],
                      'additionalProperties': false,
                    },
                  ],
                },
              },
            },
            'required': ['type'],
            'additionalProperties': false,
          },
          {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['containerReference'],
              },
              'containerId': {'type': 'string'},
            },
            'required': ['type', 'containerId'],
            'additionalProperties': false,
          },
          {
            'type': 'object',
            'properties': {
              'type': {
                'type': 'string',
                'enum': ['local'],
              },
              'skills': {
                'type': 'array',
                'items': {
                  'type': 'object',
                  'properties': {
                    'name': {'type': 'string'},
                    'description': {'type': 'string'},
                    'path': {'type': 'string'},
                  },
                  'required': ['name', 'description', 'path'],
                  'additionalProperties': false,
                },
              },
            },
            'additionalProperties': false,
          },
        ],
      },
    },
    'additionalProperties': false,
  }),
);

final _toolSearchArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'execution': {
        'type': 'string',
        'enum': ['server', 'client'],
      },
      'description': {'type': 'string'},
      'parameters': {'type': 'object'},
    },
    'additionalProperties': false,
  }),
);

final _codeInterpreterArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'container': {
        'oneOf': [
          {'type': 'string'},
          {
            'type': 'object',
            'properties': {
              'fileIds': {
                'type': 'array',
                'items': {'type': 'string'},
              },
            },
            'additionalProperties': false,
          },
        ],
      },
    },
    'additionalProperties': false,
  }),
);

final _fileSearchArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'vectorStoreIds': {
        'type': 'array',
        'items': {'type': 'string'},
      },
      'maxNumResults': {'type': 'number'},
      'ranking': {
        'type': 'object',
        'properties': {
          'ranker': {'type': 'string'},
          'scoreThreshold': {'type': 'number'},
        },
        'additionalProperties': false,
      },
      'filters': {
        'oneOf': [
          {'\$ref': '#/definitions/comparisonFilter'},
          {'\$ref': '#/definitions/compoundFilter'},
        ],
      },
    },
    'required': ['vectorStoreIds'],
    'additionalProperties': false,
    'definitions': {
      'comparisonFilter': {
        'type': 'object',
        'properties': {
          'key': {'type': 'string'},
          'type': {
            'type': 'string',
            'enum': ['eq', 'ne', 'gt', 'gte', 'lt', 'lte', 'in', 'nin'],
          },
          'value': {
            'oneOf': [
              {'type': 'string'},
              {'type': 'number'},
              {'type': 'boolean'},
              {
                'type': 'array',
                'items': {
                  'oneOf': [
                    {'type': 'string'},
                    {'type': 'number'},
                  ],
                },
              },
            ],
          },
        },
        'required': ['key', 'type', 'value'],
        'additionalProperties': false,
      },
      'compoundFilter': {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['and', 'or'],
          },
          'filters': {
            'type': 'array',
            'items': {
              'oneOf': [
                {'\$ref': '#/definitions/comparisonFilter'},
                {'\$ref': '#/definitions/compoundFilter'},
              ],
            },
          },
        },
        'required': ['type', 'filters'],
        'additionalProperties': false,
      },
    },
  }),
);

final _webSearchArgsValidator = JsonSchemaValidator.fromContract(
  const JsonSchema({
    'type': 'object',
    'properties': {
      'externalWebAccess': {'type': 'boolean'},
      'filters': {
        'type': 'object',
        'properties': {
          'allowedDomains': {
            'type': 'array',
            'items': {'type': 'string'},
          },
        },
        'additionalProperties': false,
      },
      'searchContextSize': {
        'type': 'string',
        'enum': ['low', 'medium', 'high'],
      },
      'userLocation': {
        'type': 'object',
        'properties': {
          'type': {
            'type': 'string',
            'enum': ['approximate'],
          },
          'country': {'type': 'string'},
          'city': {'type': 'string'},
          'region': {'type': 'string'},
          'timezone': {'type': 'string'},
        },
        'required': ['type'],
        'additionalProperties': false,
      },
    },
    'additionalProperties': false,
  }),
);

/// [prepareOpenAiResponsesTools] 的结果:tools 数组 + toolChoice + 告警。
final class OpenAiResponsesToolsResult {
  /// 用给定字段构造一个工具准备结果。
  const OpenAiResponsesToolsResult({
    this.tools,
    this.toolChoice,
    required this.warnings,
  });

  /// 准备好的 wire tools 数组;`null` 表示不下发 `tools` 字段。
  final List<JsonObject>? tools;

  /// 准备好的 wire toolChoice;`null` 表示不下发该字段。
  final Object? toolChoice;

  /// 准备过程中产生的告警。
  final List<Warning> warnings;
}

/// 把契约工具列表 + toolChoice 转换为 Responses API 的 `tools`/
/// `tool_choice` 请求字段。
///
/// 首版仅支持 [FunctionTool](wire 形状为扁平 `{type:'function', name,
/// description, parameters, strict?}`,**无** chat wire 的 `function`
/// 包装层,逐字对照 raw `openai-responses-prepare-tools.ts` 的
/// `prepareFunctionTool`)。当前额外支持 OpenAI 当前 Responses
/// provider-defined tools;其他 [ProviderTool] 追加 [UnsupportedWarning] 并跳过,
/// 不加入 `tools` 数组、不 throw。
OpenAiResponsesToolsResult prepareOpenAiResponsesTools({
  required List<LanguageModelTool>? tools,
  required ToolChoice? toolChoice,
}) {
  final resolvedTools = (tools == null || tools.isEmpty) ? null : tools;
  final warnings = <Warning>[];

  if (resolvedTools == null) {
    return OpenAiResponsesToolsResult(warnings: warnings);
  }

  final openaiTools = <JsonObject>[];
  for (final tool in resolvedTools) {
    switch (tool) {
      case FunctionTool():
        openaiTools.add(<String, Object?>{
          'type': 'function',
          'name': tool.name,
          if (tool.description != null) 'description': tool.description,
          'parameters': tool.inputSchema.value,
          if (tool.strict != null) 'strict': tool.strict,
        });
      case ProviderTool(:final id, :final name, :final args):
        switch (id) {
          case 'openai.apply_patch':
            openaiTools.add(_prepareApplyPatchTool());
          case 'openai.code_interpreter':
            openaiTools.add(_prepareCodeInterpreterTool(args));
          case 'openai.custom':
            openaiTools.add(_prepareCustomTool(name, args));
          case 'openai.file_search':
            openaiTools.add(_prepareFileSearchTool(args));
          case 'openai.image_generation':
            openaiTools.add(_prepareImageGenerationTool(args));
          case 'openai.mcp':
            openaiTools.add(_prepareMcpTool(args));
          case 'openai.shell':
            openaiTools.add(_prepareShellTool(args));
          case 'openai.tool_search':
            openaiTools.add(_prepareToolSearchTool(args));
          case 'openai.web_search':
            openaiTools.add(_prepareWebSearchTool(args));
          default:
            warnings.add(UnsupportedWarning('provider tool $id'));
        }
    }
  }

  // 所有工具都因不支持被过滤后,openaiTools 为空;此时应像"一开始就没传
  // 工具"一样省略 tools/tool_choice,而不是发送空数组(OpenAI 拒绝空
  // `tools`),让调用方优雅降级为无工具请求,Warning 仍保留。
  if (openaiTools.isEmpty) {
    return OpenAiResponsesToolsResult(warnings: warnings);
  }

  if (toolChoice == null) {
    return OpenAiResponsesToolsResult(tools: openaiTools, warnings: warnings);
  }

  final wireToolChoice = switch (toolChoice) {
    ToolChoiceAuto() => 'auto',
    ToolChoiceNone() => 'none',
    ToolChoiceRequired() => 'required',
    ToolChoiceTool(:final toolName) => _resolveToolChoiceTool(
        toolName,
        resolvedTools,
        warnings,
      ),
  };

  return OpenAiResponsesToolsResult(
    tools: openaiTools,
    toolChoice: wireToolChoice,
    warnings: warnings,
  );
}

JsonObject _resolveToolChoiceTool(
  String toolName,
  List<LanguageModelTool> tools,
  List<Warning> warnings,
) {
  if (_hasFunctionToolNamed(tools, toolName)) {
    return <String, Object?>{'type': 'function', 'name': toolName};
  }

  if (toolName == 'web_search' &&
      _hasProviderTool(tools, id: 'openai.web_search')) {
    return <String, Object?>{'type': 'web_search'};
  }

  if (toolName == 'code_interpreter' &&
      _hasProviderTool(tools, id: 'openai.code_interpreter')) {
    return <String, Object?>{'type': 'code_interpreter'};
  }

  if (toolName == 'file_search' &&
      _hasProviderTool(tools, id: 'openai.file_search')) {
    return <String, Object?>{'type': 'file_search'};
  }

  if (toolName == 'image_generation' &&
      _hasProviderTool(tools, id: 'openai.image_generation')) {
    return <String, Object?>{'type': 'image_generation'};
  }

  if (toolName == 'mcp') {
    final tool = _providerToolById(tools, id: 'openai.mcp');
    if (tool != null) {
      return <String, Object?>{
        'type': 'mcp',
        'server_label': tool.args['serverLabel'],
      };
    }
  }

  if (toolName.startsWith('mcp.')) {
    final mcpToolName = toolName.substring('mcp.'.length);
    final tool = _mcpProviderToolForName(tools, mcpToolName);
    if (tool != null) {
      return <String, Object?>{
        'type': 'mcp',
        'server_label': tool.args['serverLabel'],
        'name': mcpToolName,
      };
    }
  }

  if (toolName == 'apply_patch' &&
      _hasProviderTool(tools, id: 'openai.apply_patch')) {
    return <String, Object?>{'type': 'apply_patch'};
  }

  if (toolName == 'tool_search' &&
      _hasProviderTool(tools, id: 'openai.tool_search')) {
    return <String, Object?>{'type': 'tool_search'};
  }

  if (toolName == 'shell' && _hasProviderTool(tools, id: 'openai.shell')) {
    return <String, Object?>{'type': 'shell'};
  }

  final customTool = _customProviderToolByName(tools, toolName);
  if (customTool != null) {
    return <String, Object?>{'type': 'custom', 'name': toolName};
  }

  if (_unsupportedBuiltInToolChoiceNames.contains(toolName)) {
    warnings.add(
      UnsupportedWarning(
        'allowed tool choice for built-in tool "$toolName"',
        details: 'built-in Responses tools are not supported yet; the tool '
            'choice is downgraded to a plain function reference',
      ),
    );
  }
  return <String, Object?>{'type': 'function', 'name': toolName};
}

bool _hasFunctionToolNamed(List<LanguageModelTool> tools, String name) {
  for (final tool in tools) {
    if (tool case FunctionTool(name: final toolName) when toolName == name) {
      return true;
    }
  }
  return false;
}

bool _hasProviderTool(List<LanguageModelTool> tools, {required String id}) {
  return _providerToolById(tools, id: id) != null;
}

ProviderTool? _providerToolById(
  List<LanguageModelTool> tools, {
  required String id,
}) {
  for (final tool in tools) {
    if (tool case ProviderTool(id: final toolId) when toolId == id) {
      return tool;
    }
  }
  return null;
}

ProviderTool? _customProviderToolByName(
  List<LanguageModelTool> tools,
  String name,
) {
  for (final tool in tools) {
    if (tool case ProviderTool(id: 'openai.custom', name: final toolName)
        when toolName == name) {
      return tool;
    }
  }
  return null;
}

ProviderTool? _mcpProviderToolForName(
  List<LanguageModelTool> tools,
  String name,
) {
  for (final tool in tools) {
    if (tool case ProviderTool(id: 'openai.mcp', args: final args)
        when _mcpAllowedToolsContains(args['allowedTools'], name)) {
      return tool;
    }
  }
  return null;
}

bool _mcpAllowedToolsContains(Object? allowedTools, String name) {
  return switch (allowedTools) {
    null => true,
    List<Object?> names => names.contains(name),
    Map<String, Object?> values => switch (values['toolNames']) {
        null => true,
        List<Object?> names => names.contains(name),
        _ => false,
      },
    _ => false,
  };
}

JsonObject _prepareCodeInterpreterTool(Map<String, Object?> args) {
  final value =
      validateTypes(args, _codeInterpreterArgsValidator) as JsonObject;
  final container = value['container'];

  return <String, Object?>{
    'type': 'code_interpreter',
    'container': switch (container) {
      null => <String, Object?>{'type': 'auto'},
      String() => container,
      JsonObject() => <String, Object?>{
          'type': 'auto',
          'file_ids': container['fileIds'],
        }..removeWhere((_, value) => value == null),
      _ => throw StateError('validated container has unexpected shape'),
    },
  };
}

JsonObject _prepareApplyPatchTool() {
  return <String, Object?>{'type': 'apply_patch'};
}

JsonObject _prepareCustomTool(String name, Map<String, Object?> args) {
  final value = validateTypes(args, _customArgsValidator) as JsonObject;

  return <String, Object?>{
    'type': 'custom',
    'name': name,
    'description': value['description'],
    'format': value['format'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareToolSearchTool(Map<String, Object?> args) {
  final value = validateTypes(args, _toolSearchArgsValidator) as JsonObject;

  return <String, Object?>{
    'type': 'tool_search',
    'execution': value['execution'],
    'description': value['description'],
    'parameters': value['parameters'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareShellTool(Map<String, Object?> args) {
  final value = validateTypes(args, _shellArgsValidator) as JsonObject;
  final environment = value['environment'] as JsonObject?;

  return <String, Object?>{
    'type': 'shell',
    'environment':
        environment == null ? null : _prepareShellEnvironment(environment),
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareShellEnvironment(JsonObject value) {
  return switch (value['type']) {
    'containerReference' => <String, Object?>{
        'type': 'container_reference',
        'container_id': value['containerId'],
      },
    'containerAuto' => <String, Object?>{
        'type': 'container_auto',
        'file_ids': value['fileIds'],
        'memory_limit': value['memoryLimit'],
        'network_policy': switch (value['networkPolicy']) {
          JsonObject networkPolicy => _prepareShellNetworkPolicy(networkPolicy),
          null => null,
          _ => throw StateError('validated networkPolicy has unexpected shape'),
        },
        'skills': switch (value['skills']) {
          List<Object?> skills => _prepareShellSkills(skills),
          null => null,
          _ => throw StateError('validated shell skills have unexpected shape'),
        },
      }..removeWhere((_, value) => value == null),
    'local' || null => <String, Object?>{
        'type': 'local',
        'skills': value['skills'],
      }..removeWhere((_, value) => value == null),
    _ => throw StateError('validated shell environment has unexpected type'),
  };
}

JsonObject _prepareShellNetworkPolicy(JsonObject value) {
  return switch (value['type']) {
    'disabled' => <String, Object?>{'type': 'disabled'},
    'allowlist' => <String, Object?>{
        'type': 'allowlist',
        'allowed_domains': value['allowedDomains'],
        'domain_secrets': value['domainSecrets'],
      }..removeWhere((_, value) => value == null),
    _ => throw StateError('validated shell network policy has unexpected type'),
  };
}

List<JsonObject> _prepareShellSkills(List<Object?> values) {
  return values.map((value) {
    if (value is! JsonObject) {
      throw StateError('validated shell skill has unexpected shape');
    }
    return switch (value['type']) {
      'skillReference' => <String, Object?>{
          'type': 'skill_reference',
          'skill_id': resolveProviderReference(
            reference: Map<String, String>.from(
              value['providerReference'] as Map<Object?, Object?>,
            ),
            provider: 'openai',
          ),
          'version': value['version'] ?? 'latest',
        },
      'inline' => _prepareInlineShellSkill(value),
      _ => throw StateError('validated shell skill has unexpected type'),
    };
  }).toList();
}

JsonObject _prepareInlineShellSkill(JsonObject value) {
  final source = value['source'];
  if (source is! JsonObject) {
    throw StateError('validated inline shell skill has unexpected source');
  }
  return <String, Object?>{
    'type': 'inline',
    'name': value['name'],
    'description': value['description'],
    'source': {
      'type': 'base64',
      'media_type': source['mediaType'],
      'data': source['data'],
    },
  };
}

JsonObject _prepareImageGenerationTool(Map<String, Object?> args) {
  final value =
      validateTypes(args, _imageGenerationArgsValidator) as JsonObject;
  final inputImageMask = value['inputImageMask'] as JsonObject?;
  final wireInputImageMask = inputImageMask == null
      ? null
      : (<String, Object?>{
          'file_id': inputImageMask['fileId'],
          'image_url': inputImageMask['imageUrl'],
        }..removeWhere((_, value) => value == null));

  return <String, Object?>{
    'type': 'image_generation',
    'action': value['action'],
    'background': value['background'],
    'input_fidelity': value['inputFidelity'],
    'input_image_mask': wireInputImageMask,
    'model': value['model'],
    'moderation': value['moderation'],
    'output_compression': value['outputCompression'],
    'output_format': value['outputFormat'],
    'partial_images': value['partialImages'],
    'quality': value['quality'],
    'size': value['size'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareMcpTool(Map<String, Object?> args) {
  final value = validateTypes(args, _mcpArgsValidator) as JsonObject;
  if (value['serverUrl'] == null && value['connectorId'] == null) {
    throw TypeValidationError(
      value: args,
      cause: 'OpenAI mcp provider tool requires serverUrl or connectorId',
    );
  }

  final allowedTools = value['allowedTools'];
  final wireAllowedTools = switch (allowedTools) {
    null => null,
    List<Object?>() => allowedTools,
    JsonObject() => <String, Object?>{
        'read_only': allowedTools['readOnly'],
        'tool_names': allowedTools['toolNames'],
      }..removeWhere((_, value) => value == null),
    _ => throw StateError('validated allowedTools has unexpected shape'),
  };

  final requireApproval = value['requireApproval'];
  final wireRequireApproval = switch (requireApproval) {
    null => null,
    String() => requireApproval,
    JsonObject() => _prepareMcpRequireApproval(requireApproval),
    _ => throw StateError('validated requireApproval has unexpected shape'),
  };

  return <String, Object?>{
    'type': 'mcp',
    'server_label': value['serverLabel'],
    'allowed_tools': wireAllowedTools,
    'authorization': value['authorization'],
    'connector_id': value['connectorId'],
    'headers': value['headers'],
    'require_approval': wireRequireApproval,
    'server_description': value['serverDescription'],
    'server_url': value['serverUrl'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareMcpRequireApproval(JsonObject value) {
  return <String, Object?>{
    'always': switch (value['always']) {
      JsonObject filter => _prepareMcpApprovalFilter(filter),
      null => null,
      _ => throw StateError('validated always approval has unexpected shape'),
    },
    'never': switch (value['never']) {
      JsonObject filter => _prepareMcpApprovalFilter(filter),
      null => null,
      _ => throw StateError('validated never approval has unexpected shape'),
    },
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareMcpApprovalFilter(JsonObject value) {
  return <String, Object?>{
    'read_only': value['readOnly'],
    'tool_names': value['toolNames'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareFileSearchTool(Map<String, Object?> args) {
  final value = validateTypes(args, _fileSearchArgsValidator) as JsonObject;
  final ranking = value['ranking'] as JsonObject?;
  final wireRanking = ranking == null
      ? null
      : (<String, Object?>{
          'ranker': ranking['ranker'],
          'score_threshold': ranking['scoreThreshold'],
        }..removeWhere((_, value) => value == null));

  return <String, Object?>{
    'type': 'file_search',
    'vector_store_ids': value['vectorStoreIds'],
    'max_num_results': value['maxNumResults'],
    'ranking_options': wireRanking,
    'filters': value['filters'],
  }..removeWhere((_, value) => value == null);
}

JsonObject _prepareWebSearchTool(Map<String, Object?> args) {
  final value = validateTypes(args, _webSearchArgsValidator) as JsonObject;
  final filters = value['filters'] as JsonObject?;
  final wireFilters = filters == null
      ? null
      : (<String, Object?>{
          'allowed_domains': filters['allowedDomains'],
        }..removeWhere((_, value) => value == null));

  return <String, Object?>{
    'type': 'web_search',
    'external_web_access': value['externalWebAccess'],
    'filters': wireFilters,
    'search_context_size': value['searchContextSize'],
    'user_location': value['userLocation'],
  }..removeWhere((_, value) => value == null);
}
