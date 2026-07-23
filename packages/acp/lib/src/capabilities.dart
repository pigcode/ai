import 'package:equatable/equatable.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'models.dart';
import 'schema.dart';

/// Immutable capabilities advertised by an ACP client.
final class AcpClientCapabilities extends Equatable {
  factory AcpClientCapabilities({
    bool readTextFile = false,
    bool writeTextFile = false,
    bool terminal = false,
    bool booleanConfigOptions = false,
  }) {
    return AcpClientCapabilities.fromJson(<String, Object?>{
      'fs': <String, Object?>{
        'readTextFile': readTextFile,
        'writeTextFile': writeTextFile,
      },
      'terminal': terminal,
      if (booleanConfigOptions)
        'session': <String, Object?>{
          'configOptions': <String, Object?>{
            'boolean': <String, Object?>{},
          },
        },
    });
  }

  factory AcpClientCapabilities.fromJson(JsonValue value) {
    final raw = AcpSchema.instance.validateDefinition(
      'ClientCapabilities',
      value,
    )! as JsonObject;
    final fs = _optionalObject(raw['fs']);
    final session = _optionalObject(raw['session']);
    final configOptions = _optionalObject(session?['configOptions']);
    return AcpClientCapabilities._(
      raw: raw,
      readTextFile: fs?['readTextFile'] == true,
      writeTextFile: fs?['writeTextFile'] == true,
      terminal: raw['terminal'] == true,
      booleanConfigOptions: _optionalObject(configOptions?['boolean']) != null,
    );
  }

  const AcpClientCapabilities._({
    required this.raw,
    required this.readTextFile,
    required this.writeTextFile,
    required this.terminal,
    required this.booleanConfigOptions,
  });

  final JsonObject raw;
  final bool readTextFile;
  final bool writeTextFile;
  final bool terminal;
  final bool booleanConfigOptions;

  JsonObject toJson() => raw;

  Set<String> get requiredHandlerMethods => <String>{
        if (readTextFile) 'fs/read_text_file',
        if (writeTextFile) 'fs/write_text_file',
        if (terminal) ...const <String>{
          'terminal/create',
          'terminal/output',
          'terminal/release',
          'terminal/wait_for_exit',
          'terminal/kill',
        },
      };

  @override
  List<Object?> get props => <Object?>[
        readTextFile,
        writeTextFile,
        terminal,
        booleanConfigOptions,
      ];
}

/// Immutable capabilities advertised by an ACP agent.
final class AcpAgentCapabilities extends Equatable {
  factory AcpAgentCapabilities({
    bool loadSession = false,
    bool promptImage = false,
    bool promptAudio = false,
    bool promptEmbeddedContext = false,
    bool mcpHttp = false,
    bool mcpSse = false,
    bool sessionList = false,
    bool sessionDelete = false,
    bool additionalDirectories = false,
    bool sessionResume = false,
    bool sessionClose = false,
    bool logout = false,
  }) {
    return AcpAgentCapabilities.fromJson(<String, Object?>{
      'loadSession': loadSession,
      'promptCapabilities': <String, Object?>{
        'image': promptImage,
        'audio': promptAudio,
        'embeddedContext': promptEmbeddedContext,
      },
      'mcpCapabilities': <String, Object?>{
        'http': mcpHttp,
        'sse': mcpSse,
      },
      'sessionCapabilities': <String, Object?>{
        if (sessionList) 'list': <String, Object?>{},
        if (sessionDelete) 'delete': <String, Object?>{},
        if (additionalDirectories) 'additionalDirectories': <String, Object?>{},
        if (sessionResume) 'resume': <String, Object?>{},
        if (sessionClose) 'close': <String, Object?>{},
      },
      'auth': <String, Object?>{
        if (logout) 'logout': <String, Object?>{},
      },
    });
  }

  factory AcpAgentCapabilities.fromJson(JsonValue value) {
    final raw = AcpSchema.instance.validateDefinition(
      'AgentCapabilities',
      value,
    )! as JsonObject;
    final prompt = _optionalObject(raw['promptCapabilities']);
    final mcp = _optionalObject(raw['mcpCapabilities']);
    final session = _optionalObject(raw['sessionCapabilities']);
    final auth = _optionalObject(raw['auth']);
    return AcpAgentCapabilities._(
      raw: raw,
      loadSession: raw['loadSession'] == true,
      promptImage: prompt?['image'] == true,
      promptAudio: prompt?['audio'] == true,
      promptEmbeddedContext: prompt?['embeddedContext'] == true,
      mcpHttp: mcp?['http'] == true,
      mcpSse: mcp?['sse'] == true,
      sessionList: _optionalObject(session?['list']) != null,
      sessionDelete: _optionalObject(session?['delete']) != null,
      additionalDirectories:
          _optionalObject(session?['additionalDirectories']) != null,
      sessionResume: _optionalObject(session?['resume']) != null,
      sessionClose: _optionalObject(session?['close']) != null,
      logout: _optionalObject(auth?['logout']) != null,
    );
  }

  const AcpAgentCapabilities._({
    required this.raw,
    required this.loadSession,
    required this.promptImage,
    required this.promptAudio,
    required this.promptEmbeddedContext,
    required this.mcpHttp,
    required this.mcpSse,
    required this.sessionList,
    required this.sessionDelete,
    required this.additionalDirectories,
    required this.sessionResume,
    required this.sessionClose,
    required this.logout,
  });

  final JsonObject raw;
  final bool loadSession;
  final bool promptImage;
  final bool promptAudio;
  final bool promptEmbeddedContext;
  final bool mcpHttp;
  final bool mcpSse;
  final bool sessionList;
  final bool sessionDelete;
  final bool additionalDirectories;
  final bool sessionResume;
  final bool sessionClose;
  final bool logout;

  JsonObject toJson() => raw;

  Set<String> get requiredHandlerMethods => <String>{
        if (loadSession) 'session/load',
        if (sessionList) 'session/list',
        if (sessionDelete) 'session/delete',
        if (sessionResume) 'session/resume',
        if (sessionClose) 'session/close',
        if (logout) 'logout',
      };

  @override
  List<Object?> get props => <Object?>[
        loadSession,
        promptImage,
        promptAudio,
        promptEmbeddedContext,
        mcpHttp,
        mcpSse,
        sessionList,
        sessionDelete,
        additionalDirectories,
        sessionResume,
        sessionClose,
        logout,
      ];
}

/// Immutable capability snapshot established by initialize.
final class AcpNegotiatedCapabilities {
  const AcpNegotiatedCapabilities({
    required this.protocolVersion,
    required this.client,
    required this.agent,
  });

  final int protocolVersion;
  final AcpClientCapabilities client;
  final AcpAgentCapabilities agent;

  bool supportsMethod(String method) {
    final descriptor = acpMethodsByName[method];
    if (descriptor == null) {
      return false;
    }
    return switch (method) {
      'session/load' => agent.loadSession,
      'session/list' => agent.sessionList,
      'session/delete' => agent.sessionDelete,
      'session/resume' => agent.sessionResume,
      'session/close' => agent.sessionClose,
      'logout' => agent.logout,
      'fs/read_text_file' => client.readTextFile,
      'fs/write_text_file' => client.writeTextFile,
      'terminal/create' ||
      'terminal/output' ||
      'terminal/release' ||
      'terminal/wait_for_exit' ||
      'terminal/kill' =>
        client.terminal,
      _ => true,
    };
  }
}

JsonObject? _optionalObject(Object? value) =>
    value is Map<String, Object?> ? value : null;
