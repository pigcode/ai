import 'package:equatable/equatable.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'models.dart';
import 'schema.dart';

final class McpClientCapabilities extends Equatable {
  factory McpClientCapabilities({
    bool roots = false,
    bool rootsListChanged = false,
    bool sampling = false,
    bool samplingContext = false,
    bool samplingTools = false,
    bool elicitationForm = false,
    bool elicitationUrl = false,
    bool taskCancel = false,
    bool taskList = false,
    bool taskSampling = false,
    bool taskElicitation = false,
  }) {
    final hasTasks = taskCancel || taskList || taskSampling || taskElicitation;
    return McpClientCapabilities.fromJson(<String, Object?>{
      if (roots)
        'roots': <String, Object?>{
          if (rootsListChanged) 'listChanged': true,
        },
      if (sampling)
        'sampling': <String, Object?>{
          if (samplingContext) 'context': <String, Object?>{},
          if (samplingTools) 'tools': <String, Object?>{},
        },
      if (elicitationForm || elicitationUrl)
        'elicitation': <String, Object?>{
          if (elicitationForm) 'form': <String, Object?>{},
          if (elicitationUrl) 'url': <String, Object?>{},
        },
      if (hasTasks)
        'tasks': <String, Object?>{
          if (taskCancel) 'cancel': <String, Object?>{},
          if (taskList) 'list': <String, Object?>{},
          if (taskSampling || taskElicitation)
            'requests': <String, Object?>{
              if (taskSampling)
                'sampling': <String, Object?>{
                  'createMessage': <String, Object?>{},
                },
              if (taskElicitation)
                'elicitation': <String, Object?>{
                  'create': <String, Object?>{},
                },
            },
        },
    });
  }

  factory McpClientCapabilities.fromJson(JsonValue value) {
    final raw = McpSchema.instance.validateDefinition(
      'ClientCapabilities',
      value,
    )! as JsonObject;
    final roots = _object(raw['roots']);
    final sampling = _object(raw['sampling']);
    final elicitation = _object(raw['elicitation']);
    final tasks = _object(raw['tasks']);
    final requests = _object(tasks?['requests']);
    final taskSampling = _object(requests?['sampling']);
    final taskElicitation = _object(requests?['elicitation']);
    return McpClientCapabilities._(
      raw: raw,
      roots: roots != null,
      rootsListChanged: roots?['listChanged'] == true,
      sampling: sampling != null,
      samplingContext: _object(sampling?['context']) != null,
      samplingTools: _object(sampling?['tools']) != null,
      // Pre-2025-11 clients advertised form elicitation as an empty object.
      // Retain that interoperable meaning while preferring the explicit form
      // capability introduced by the pinned protocol version.
      elicitationForm: elicitation != null &&
          (elicitation.isEmpty || _object(elicitation['form']) != null),
      elicitationUrl: _object(elicitation?['url']) != null,
      taskCancel: _object(tasks?['cancel']) != null,
      taskList: _object(tasks?['list']) != null,
      taskSampling: _object(taskSampling?['createMessage']) != null,
      taskElicitation: _object(taskElicitation?['create']) != null,
      hasTasks: tasks != null,
    );
  }

  const McpClientCapabilities._({
    required this.raw,
    required this.roots,
    required this.rootsListChanged,
    required this.sampling,
    required this.samplingContext,
    required this.samplingTools,
    required this.elicitationForm,
    required this.elicitationUrl,
    required this.taskCancel,
    required this.taskList,
    required this.taskSampling,
    required this.taskElicitation,
    required this.hasTasks,
  });

  final JsonObject raw;
  final bool roots;
  final bool rootsListChanged;
  final bool sampling;
  final bool samplingContext;
  final bool samplingTools;
  final bool elicitationForm;
  final bool elicitationUrl;
  final bool taskCancel;
  final bool taskList;
  final bool taskSampling;
  final bool taskElicitation;
  final bool hasTasks;

  JsonObject toJson() => raw;

  Set<String> get requiredHandlerMethods => <String>{
        if (roots) 'roots/list',
        if (sampling) 'sampling/createMessage',
        if (elicitationForm || elicitationUrl) 'elicitation/create',
        if (hasTasks) ...const <String>{'tasks/get', 'tasks/result'},
        if (taskCancel) 'tasks/cancel',
        if (taskList) 'tasks/list',
      };

  @override
  List<Object?> get props => <Object?>[
        roots,
        rootsListChanged,
        sampling,
        samplingContext,
        samplingTools,
        elicitationForm,
        elicitationUrl,
        taskCancel,
        taskList,
        taskSampling,
        taskElicitation,
        hasTasks,
      ];
}

final class McpServerCapabilities extends Equatable {
  factory McpServerCapabilities({
    bool resources = false,
    bool resourceSubscribe = false,
    bool resourceListChanged = false,
    bool prompts = false,
    bool promptListChanged = false,
    bool tools = false,
    bool toolListChanged = false,
    bool completions = false,
    bool logging = false,
    bool taskCancel = false,
    bool taskList = false,
    bool taskToolCall = false,
  }) {
    final hasTasks = taskCancel || taskList || taskToolCall;
    return McpServerCapabilities.fromJson(<String, Object?>{
      if (resources)
        'resources': <String, Object?>{
          if (resourceSubscribe) 'subscribe': true,
          if (resourceListChanged) 'listChanged': true,
        },
      if (prompts)
        'prompts': <String, Object?>{
          if (promptListChanged) 'listChanged': true,
        },
      if (tools)
        'tools': <String, Object?>{
          if (toolListChanged) 'listChanged': true,
        },
      if (completions) 'completions': <String, Object?>{},
      if (logging) 'logging': <String, Object?>{},
      if (hasTasks)
        'tasks': <String, Object?>{
          if (taskCancel) 'cancel': <String, Object?>{},
          if (taskList) 'list': <String, Object?>{},
          if (taskToolCall)
            'requests': <String, Object?>{
              'tools': <String, Object?>{
                'call': <String, Object?>{},
              },
            },
        },
    });
  }

  factory McpServerCapabilities.fromJson(JsonValue value) {
    final raw = McpSchema.instance.validateDefinition(
      'ServerCapabilities',
      value,
    )! as JsonObject;
    final resources = _object(raw['resources']);
    final prompts = _object(raw['prompts']);
    final tools = _object(raw['tools']);
    final tasks = _object(raw['tasks']);
    final requests = _object(tasks?['requests']);
    final taskTools = _object(requests?['tools']);
    return McpServerCapabilities._(
      raw: raw,
      resources: resources != null,
      resourceSubscribe: resources?['subscribe'] == true,
      resourceListChanged: resources?['listChanged'] == true,
      prompts: prompts != null,
      promptListChanged: prompts?['listChanged'] == true,
      tools: tools != null,
      toolListChanged: tools?['listChanged'] == true,
      completions: _object(raw['completions']) != null,
      logging: _object(raw['logging']) != null,
      taskCancel: _object(tasks?['cancel']) != null,
      taskList: _object(tasks?['list']) != null,
      taskToolCall: _object(taskTools?['call']) != null,
      hasTasks: tasks != null,
    );
  }

  const McpServerCapabilities._({
    required this.raw,
    required this.resources,
    required this.resourceSubscribe,
    required this.resourceListChanged,
    required this.prompts,
    required this.promptListChanged,
    required this.tools,
    required this.toolListChanged,
    required this.completions,
    required this.logging,
    required this.taskCancel,
    required this.taskList,
    required this.taskToolCall,
    required this.hasTasks,
  });

  final JsonObject raw;
  final bool resources;
  final bool resourceSubscribe;
  final bool resourceListChanged;
  final bool prompts;
  final bool promptListChanged;
  final bool tools;
  final bool toolListChanged;
  final bool completions;
  final bool logging;
  final bool taskCancel;
  final bool taskList;
  final bool taskToolCall;
  final bool hasTasks;

  JsonObject toJson() => raw;

  Set<String> get requiredHandlerMethods => <String>{
        if (resources) ...const <String>{
          'resources/list',
          'resources/templates/list',
          'resources/read',
        },
        if (resourceSubscribe) ...const <String>{
          'resources/subscribe',
          'resources/unsubscribe',
        },
        if (prompts) ...const <String>{'prompts/list', 'prompts/get'},
        if (tools) ...const <String>{'tools/list', 'tools/call'},
        if (completions) 'completion/complete',
        if (logging) 'logging/setLevel',
        if (hasTasks) ...const <String>{'tasks/get', 'tasks/result'},
        if (taskCancel) 'tasks/cancel',
        if (taskList) 'tasks/list',
      };

  @override
  List<Object?> get props => <Object?>[
        resources,
        resourceSubscribe,
        resourceListChanged,
        prompts,
        promptListChanged,
        tools,
        toolListChanged,
        completions,
        logging,
        taskCancel,
        taskList,
        taskToolCall,
        hasTasks,
      ];
}

final class McpNegotiatedCapabilities {
  const McpNegotiatedCapabilities({
    required this.protocolVersion,
    required this.client,
    required this.server,
  });

  final String protocolVersion;
  final McpClientCapabilities client;
  final McpServerCapabilities server;

  bool supports(McpMethodBinding binding) {
    final method = binding.method;
    return switch (method) {
      'resources/list' ||
      'resources/templates/list' ||
      'resources/read' =>
        server.resources,
      'resources/subscribe' ||
      'resources/unsubscribe' =>
        server.resourceSubscribe,
      'prompts/list' || 'prompts/get' => server.prompts,
      'tools/list' || 'tools/call' => server.tools,
      'completion/complete' => server.completions,
      'logging/setLevel' || 'notifications/message' => server.logging,
      'notifications/resources/list_changed' => server.resourceListChanged,
      'notifications/resources/updated' => server.resources,
      'notifications/prompts/list_changed' => server.promptListChanged,
      'notifications/tools/list_changed' => server.toolListChanged,
      'sampling/createMessage' => client.sampling,
      'roots/list' => client.roots,
      'notifications/roots/list_changed' => client.rootsListChanged,
      'elicitation/create' ||
      'notifications/elicitation/complete' =>
        client.elicitationForm || client.elicitationUrl,
      'tasks/get' || 'tasks/result' => binding.sender == McpParticipant.client
          ? server.hasTasks
          : client.hasTasks,
      'tasks/cancel' => binding.sender == McpParticipant.client
          ? server.taskCancel
          : client.taskCancel,
      'tasks/list' => binding.sender == McpParticipant.client
          ? server.taskList
          : client.taskList,
      'notifications/tasks/status' => client.hasTasks || server.hasTasks,
      _ => true,
    };
  }
}

JsonObject? _object(Object? value) =>
    value is Map<String, Object?> ? value : null;
