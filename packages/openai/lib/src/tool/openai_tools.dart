import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

/// OpenAI Responses provider-executed tool factories.
const openAiTools = OpenAiTools();

/// Factory collection for OpenAI provider tools.
final class OpenAiTools {
  const OpenAiTools();

  /// Creates the current Responses API `web_search` provider-executed tool.
  ProviderTool webSearch({
    bool? externalWebAccess,
    OpenAiWebSearchFilters? filters,
    String? searchContextSize,
    OpenAiWebSearchUserLocation? userLocation,
  }) {
    final args = <String, Object?>{
      'externalWebAccess': externalWebAccess,
      'filters': filters?.toJson(),
      'searchContextSize': searchContextSize,
      'userLocation': userLocation?.toJson(),
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.web_search',
      name: 'web_search',
      args: args,
    );
  }

  /// Creates the current Responses API `file_search` provider-executed tool.
  ProviderTool fileSearch({
    required List<String> vectorStoreIds,
    int? maxNumResults,
    OpenAiFileSearchRanking? ranking,
    OpenAiFileSearchFilter? filters,
  }) {
    final args = <String, Object?>{
      'vectorStoreIds': vectorStoreIds,
      'maxNumResults': maxNumResults,
      'ranking': ranking?.toJson(),
      'filters': filters?.toJson(),
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.file_search',
      name: 'file_search',
      args: args,
    );
  }

  /// Creates the current Responses API `code_interpreter` provider-executed
  /// tool.
  ProviderTool codeInterpreter({OpenAiCodeInterpreterContainer? container}) {
    final args = <String, Object?>{
      'container': container?.toJson(),
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.code_interpreter',
      name: 'code_interpreter',
      args: args,
    );
  }

  /// Creates the current Responses API `image_generation` provider-executed
  /// tool.
  ProviderTool imageGeneration({
    String? action,
    String? background,
    String? inputFidelity,
    OpenAiImageGenerationInputImageMask? inputImageMask,
    String? model,
    String? moderation,
    int? outputCompression,
    String? outputFormat,
    int? partialImages,
    String? quality,
    String? size,
  }) {
    final args = <String, Object?>{
      'action': action,
      'background': background,
      'inputFidelity': inputFidelity,
      'inputImageMask': inputImageMask?.toJson(),
      'model': model,
      'moderation': moderation,
      'outputCompression': outputCompression,
      'outputFormat': outputFormat,
      'partialImages': partialImages,
      'quality': quality,
      'size': size,
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.image_generation',
      name: 'image_generation',
      args: args,
    );
  }

  /// Creates the current Responses API `mcp` provider-executed tool.
  ProviderTool mcp({
    required String serverLabel,
    OpenAiMcpAllowedTools? allowedTools,
    String? authorization,
    String? connectorId,
    Map<String, String>? headers,
    OpenAiMcpRequireApproval? requireApproval,
    String? serverDescription,
    String? serverUrl,
  }) {
    final args = <String, Object?>{
      'serverLabel': serverLabel,
      'allowedTools': allowedTools?.toJson(),
      'authorization': authorization,
      'connectorId': connectorId,
      'headers': headers,
      'requireApproval': requireApproval?.toJson(),
      'serverDescription': serverDescription,
      'serverUrl': serverUrl,
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.mcp',
      name: 'mcp',
      args: args,
    );
  }

  /// Creates the current Responses API `apply_patch` provider-defined tool.
  ProviderTool applyPatch() {
    return const ProviderTool(
      id: 'openai.apply_patch',
      name: 'apply_patch',
      args: {},
    );
  }

  /// Creates the current Responses API `tool_search` provider-defined tool.
  ProviderTool toolSearch({
    String? execution,
    String? description,
    JsonObject? parameters,
  }) {
    final args = <String, Object?>{
      'execution': execution,
      'description': description,
      'parameters': parameters,
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.tool_search',
      name: 'tool_search',
      args: args,
    );
  }

  /// Creates the current Responses API `custom` provider-defined tool.
  ProviderTool customTool({
    required String name,
    String? description,
    OpenAiCustomToolFormat? format,
  }) {
    final args = <String, Object?>{
      'description': description,
      'format': format?.toJson(),
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.custom',
      name: name,
      args: args,
    );
  }

  /// Creates the current Responses API `shell` provider-defined tool.
  ProviderTool shell({OpenAiShellEnvironment? environment}) {
    final args = <String, Object?>{
      'environment': environment?.toJson(),
    }..removeWhere((_, value) => value == null);

    return ProviderTool(
      id: 'openai.shell',
      name: 'shell',
      args: args,
    );
  }
}

/// Output format options for the OpenAI `custom` tool.
sealed class OpenAiCustomToolFormat extends Equatable {
  const OpenAiCustomToolFormat();

  /// Constrains custom tool output with a grammar.
  const factory OpenAiCustomToolFormat.grammar({
    required String syntax,
    required String definition,
  }) = OpenAiCustomToolGrammarFormat;

  /// Leaves custom tool output as plain text.
  const factory OpenAiCustomToolFormat.text() = OpenAiCustomToolTextFormat;

  /// Serializes this format to provider-tool arguments.
  JsonObject toJson();
}

/// Grammar output format for the OpenAI `custom` tool.
final class OpenAiCustomToolGrammarFormat extends OpenAiCustomToolFormat {
  const OpenAiCustomToolGrammarFormat({
    required this.syntax,
    required this.definition,
  });

  /// Grammar syntax: `regex` or `lark`.
  final String syntax;

  /// Grammar definition.
  final String definition;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'grammar',
      'syntax': syntax,
      'definition': definition,
    };
  }

  @override
  List<Object?> get props => [syntax, definition];
}

/// Plain text output format for the OpenAI `custom` tool.
final class OpenAiCustomToolTextFormat extends OpenAiCustomToolFormat {
  const OpenAiCustomToolTextFormat();

  @override
  JsonObject toJson() {
    return const <String, Object?>{'type': 'text'};
  }

  @override
  List<Object?> get props => const [];
}

/// Environment options for the OpenAI `shell` tool.
sealed class OpenAiShellEnvironment extends Equatable {
  const OpenAiShellEnvironment();

  /// Serializes this environment to provider-tool arguments.
  JsonObject toJson();
}

/// Auto-created container environment for the OpenAI `shell` tool.
final class OpenAiShellEnvironmentContainerAuto extends OpenAiShellEnvironment {
  const OpenAiShellEnvironmentContainerAuto({
    this.fileIds,
    this.memoryLimit,
    this.networkPolicy,
    this.skills,
  });

  /// File ids made available to the auto-created container.
  final List<String>? fileIds;

  /// Container memory limit: `1g`, `4g`, `16g`, or `64g`.
  final String? memoryLimit;

  /// Network policy for the container.
  final OpenAiShellNetworkPolicy? networkPolicy;

  /// Skills made available to the container.
  final List<OpenAiShellSkill>? skills;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'containerAuto',
      'fileIds': fileIds,
      'memoryLimit': memoryLimit,
      'networkPolicy': networkPolicy?.toJson(),
      'skills': skills?.map((skill) => skill.toJson()).toList(),
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [fileIds, memoryLimit, networkPolicy, skills];
}

/// Existing container reference for the OpenAI `shell` tool.
final class OpenAiShellEnvironmentContainerReference
    extends OpenAiShellEnvironment {
  const OpenAiShellEnvironmentContainerReference(this.containerId);

  /// Existing container id.
  final String containerId;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'containerReference',
      'containerId': containerId,
    };
  }

  @override
  List<Object?> get props => [containerId];
}

/// Local environment for the OpenAI `shell` tool.
final class OpenAiShellEnvironmentLocal extends OpenAiShellEnvironment {
  const OpenAiShellEnvironmentLocal({this.skills});

  /// Local skills exposed to the shell tool.
  final List<OpenAiShellLocalSkill>? skills;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'local',
      'skills': skills?.map((skill) => skill.toJson()).toList(),
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [skills];
}

/// Network policy options for OpenAI shell containers.
sealed class OpenAiShellNetworkPolicy extends Equatable {
  const OpenAiShellNetworkPolicy();

  /// Serializes this network policy to provider-tool arguments.
  JsonObject toJson();
}

/// Disables network access for the OpenAI shell container.
final class OpenAiShellNetworkPolicyDisabled extends OpenAiShellNetworkPolicy {
  const OpenAiShellNetworkPolicyDisabled();

  @override
  JsonObject toJson() {
    return const <String, Object?>{'type': 'disabled'};
  }

  @override
  List<Object?> get props => const [];
}

/// Allows network access only to selected domains for OpenAI shell containers.
final class OpenAiShellNetworkPolicyAllowlist extends OpenAiShellNetworkPolicy {
  const OpenAiShellNetworkPolicyAllowlist({
    required this.allowedDomains,
    this.domainSecrets,
  });

  /// Allowed root domains.
  final List<String> allowedDomains;

  /// Secrets scoped to allow-listed domains.
  final List<OpenAiShellDomainSecret>? domainSecrets;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'allowlist',
      'allowedDomains': allowedDomains,
      'domainSecrets': domainSecrets?.map((secret) => secret.toJson()).toList(),
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [allowedDomains, domainSecrets];
}

/// Domain-scoped secret for OpenAI shell network allow-lists.
final class OpenAiShellDomainSecret extends Equatable {
  const OpenAiShellDomainSecret({
    required this.domain,
    required this.name,
    required this.value,
  });

  /// Domain this secret applies to.
  final String domain;

  /// Secret name.
  final String name;

  /// Secret value.
  final String value;

  JsonObject toJson() {
    return <String, Object?>{
      'domain': domain,
      'name': name,
      'value': value,
    };
  }

  @override
  List<Object?> get props => [domain, name, value];
}

/// Container skill options for the OpenAI `shell` tool.
sealed class OpenAiShellSkill extends Equatable {
  const OpenAiShellSkill();

  /// Serializes this skill to provider-tool arguments.
  JsonObject toJson();
}

/// References an uploaded OpenAI skill for the `shell` tool.
final class OpenAiShellSkillReference extends OpenAiShellSkill {
  const OpenAiShellSkillReference({
    required this.providerReference,
    this.version,
  });

  /// Provider-specific skill id reference.
  final ProviderReference providerReference;

  /// Skill version. OpenAI defaults this to latest when omitted.
  final String? version;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'skillReference',
      'providerReference': providerReference,
      'version': version,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [providerReference, version];
}

/// Inline zip skill for the OpenAI `shell` tool.
final class OpenAiShellInlineSkill extends OpenAiShellSkill {
  const OpenAiShellInlineSkill({
    required this.name,
    required this.description,
    required this.data,
  });

  /// Skill name.
  final String name;

  /// Skill description.
  final String description;

  /// Base64-encoded zip archive.
  final String data;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': 'inline',
      'name': name,
      'description': description,
      'source': {
        'type': 'base64',
        'mediaType': 'application/zip',
        'data': data,
      },
    };
  }

  @override
  List<Object?> get props => [name, description, data];
}

/// Local skill for the OpenAI `shell` tool's local environment.
final class OpenAiShellLocalSkill extends Equatable {
  const OpenAiShellLocalSkill({
    required this.name,
    required this.description,
    required this.path,
  });

  /// Skill name.
  final String name;

  /// Skill description.
  final String description;

  /// Local filesystem path.
  final String path;

  JsonObject toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'path': path,
    };
  }

  @override
  List<Object?> get props => [name, description, path];
}

enum _OpenAiMcpAllowedToolsMode { names, filter }

/// Tool allow-list options for the OpenAI `mcp` tool.
final class OpenAiMcpAllowedTools extends Equatable {
  /// Allows only the named MCP tools.
  const OpenAiMcpAllowedTools.names(this.toolNames)
      : _mode = _OpenAiMcpAllowedToolsMode.names,
        readOnly = null;

  /// Allows tools by read-only status and/or tool names.
  const OpenAiMcpAllowedTools.filter({this.readOnly, this.toolNames})
      : _mode = _OpenAiMcpAllowedToolsMode.filter;

  final _OpenAiMcpAllowedToolsMode _mode;

  /// Whether only read-only MCP tools may be used.
  final bool? readOnly;

  /// MCP tool names allowed by this filter.
  final List<String>? toolNames;

  Object toJson() {
    return switch (_mode) {
      _OpenAiMcpAllowedToolsMode.names => List<String>.of(toolNames!),
      _OpenAiMcpAllowedToolsMode.filter => <String, Object?>{
          'readOnly': readOnly,
          'toolNames': toolNames,
        }..removeWhere((_, value) => value == null),
    };
  }

  @override
  List<Object?> get props => [_mode, readOnly, toolNames];
}

enum _OpenAiMcpRequireApprovalMode { always, never, filter }

/// Approval filter for the OpenAI `mcp` tool.
final class OpenAiMcpApprovalFilter extends Equatable {
  /// Creates an MCP approval filter by read-only status and/or tool names.
  const OpenAiMcpApprovalFilter({this.readOnly, this.toolNames});

  /// Whether this filter covers read-only MCP tools.
  final bool? readOnly;

  /// MCP tool names covered by this filter.
  final List<String>? toolNames;

  JsonObject toJson() {
    return <String, Object?>{
      'readOnly': readOnly,
      'toolNames': toolNames,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [readOnly, toolNames];
}

/// Approval policy options for the OpenAI `mcp` tool.
final class OpenAiMcpRequireApproval extends Equatable {
  /// Requires approval for every MCP tool call.
  const OpenAiMcpRequireApproval.always({
    this.readOnly,
    this.toolNames,
  })  : _mode = _OpenAiMcpRequireApprovalMode.always,
        always = null,
        never = null;

  /// Never requires approval, optionally only for filtered MCP tools.
  const OpenAiMcpRequireApproval.never({
    this.readOnly,
    this.toolNames,
  })  : _mode = _OpenAiMcpRequireApprovalMode.never,
        always = null,
        never = null;

  /// Requires approval according to explicit always/never filters.
  const OpenAiMcpRequireApproval.filter({
    this.always,
    this.never,
  })  : _mode = _OpenAiMcpRequireApprovalMode.filter,
        readOnly = null,
        toolNames = null;

  final _OpenAiMcpRequireApprovalMode _mode;

  /// Whether this single-policy filter covers read-only MCP tools.
  final bool? readOnly;

  /// MCP tool names covered by this single-policy filter.
  final List<String>? toolNames;

  /// MCP tools that always require approval.
  final OpenAiMcpApprovalFilter? always;

  /// MCP tools that never require approval.
  final OpenAiMcpApprovalFilter? never;

  Object toJson() {
    return switch (_mode) {
      _OpenAiMcpRequireApprovalMode.always
          when readOnly == null && toolNames == null =>
        'always',
      _OpenAiMcpRequireApprovalMode.always => <String, Object?>{
          'always': _approvalFilterToJson(
            readOnly: readOnly,
            toolNames: toolNames,
          ),
        },
      _OpenAiMcpRequireApprovalMode.never
          when readOnly == null && toolNames == null =>
        'never',
      _OpenAiMcpRequireApprovalMode.never => <String, Object?>{
          'never': _approvalFilterToJson(
            readOnly: readOnly,
            toolNames: toolNames,
          ),
        },
      _OpenAiMcpRequireApprovalMode.filter => <String, Object?>{
          'always': always?.toJson(),
          'never': never?.toJson(),
        }..removeWhere((_, value) => value == null),
    };
  }

  @override
  List<Object?> get props => [_mode, readOnly, toolNames, always, never];
}

JsonObject _approvalFilterToJson({
  bool? readOnly,
  List<String>? toolNames,
}) {
  return <String, Object?>{
    'readOnly': readOnly,
    'toolNames': toolNames,
  }..removeWhere((_, value) => value == null);
}

/// Container options for the OpenAI `code_interpreter` tool.
final class OpenAiCodeInterpreterContainer extends Equatable {
  const OpenAiCodeInterpreterContainer({this.fileIds}) : id = null;

  /// Uses an existing OpenAI code interpreter container.
  const OpenAiCodeInterpreterContainer.id(this.id) : fileIds = null;

  /// Existing container id, when reusing a container.
  final String? id;

  /// Uploaded file ids to make available to an auto-created container.
  final List<String>? fileIds;

  Object toJson() {
    final containerId = id;
    if (containerId != null) {
      return containerId;
    }

    return <String, Object?>{
      'fileIds': fileIds,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [id, fileIds];
}

/// Mask options for the OpenAI `image_generation` tool.
final class OpenAiImageGenerationInputImageMask extends Equatable {
  const OpenAiImageGenerationInputImageMask({this.fileId, this.imageUrl});

  /// OpenAI file id for the mask image.
  final String? fileId;

  /// Data URL or URL string for the mask image.
  final String? imageUrl;

  JsonObject toJson() {
    return <String, Object?>{
      'fileId': fileId,
      'imageUrl': imageUrl,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [fileId, imageUrl];
}

/// Ranking options for the OpenAI `file_search` tool.
final class OpenAiFileSearchRanking extends Equatable {
  const OpenAiFileSearchRanking({this.ranker, this.scoreThreshold});

  /// The ranker to use.
  final String? ranker;

  /// Minimum relevance score threshold.
  final num? scoreThreshold;

  JsonObject toJson() {
    return <String, Object?>{
      'ranker': ranker,
      'scoreThreshold': scoreThreshold,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [ranker, scoreThreshold];
}

/// Base type for OpenAI `file_search` filters.
sealed class OpenAiFileSearchFilter extends Equatable {
  const OpenAiFileSearchFilter();

  /// Serializes this filter to the Responses API provider-tool arguments shape.
  JsonObject toJson();
}

/// Comparison filter for the OpenAI `file_search` tool.
final class OpenAiFileSearchComparisonFilter extends OpenAiFileSearchFilter {
  const OpenAiFileSearchComparisonFilter({
    required this.key,
    required this.type,
    required this.value,
  });

  /// Attribute key to compare.
  final String key;

  /// Comparison operator: `eq`, `ne`, `gt`, `gte`, `lt`, `lte`, `in`, or `nin`.
  final String type;

  /// Comparison value: string, number, boolean, or a string/number list.
  final JsonValue value;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'key': key,
      'type': type,
      'value': value,
    };
  }

  @override
  List<Object?> get props => [key, type, value];
}

/// Compound filter for the OpenAI `file_search` tool.
final class OpenAiFileSearchCompoundFilter extends OpenAiFileSearchFilter {
  const OpenAiFileSearchCompoundFilter({
    required this.type,
    required this.filters,
  });

  /// Compound operator: `and` or `or`.
  final String type;

  /// Child filters.
  final List<OpenAiFileSearchFilter> filters;

  @override
  JsonObject toJson() {
    return <String, Object?>{
      'type': type,
      'filters': filters.map((filter) => filter.toJson()).toList(),
    };
  }

  @override
  List<Object?> get props => [type, filters];
}

/// Domain filters for the OpenAI `web_search` tool.
final class OpenAiWebSearchFilters extends Equatable {
  const OpenAiWebSearchFilters({this.allowedDomains});

  /// Allowed root domains. Subdomains are allowed by OpenAI.
  final List<String>? allowedDomains;

  JsonObject toJson() {
    return <String, Object?>{
      'allowedDomains': allowedDomains,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [allowedDomains];
}

/// Approximate user location for geographically relevant OpenAI web search.
final class OpenAiWebSearchUserLocation extends Equatable {
  const OpenAiWebSearchUserLocation({
    this.country,
    this.city,
    this.region,
    this.timezone,
  });

  /// Two-letter ISO country code, for example `US`.
  final String? country;

  /// City name.
  final String? city;

  /// Region name.
  final String? region;

  /// IANA timezone, for example `America/Los_Angeles`.
  final String? timezone;

  JsonObject toJson() {
    return <String, Object?>{
      'type': 'approximate',
      'country': country,
      'city': city,
      'region': region,
      'timezone': timezone,
    }..removeWhere((_, value) => value == null);
  }

  @override
  List<Object?> get props => [country, city, region, timezone];
}
