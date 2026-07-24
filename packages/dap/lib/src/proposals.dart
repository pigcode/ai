import 'dart:async';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'models.dart';

sealed class DapProposal {
  const DapProposal({
    required this.command,
    required this.arguments,
  });

  final String command;
  final JsonObject arguments;

  JsonObject toJson() => arguments;
}

final class DapRunInTerminalProposal extends DapProposal {
  DapRunInTerminalProposal._(JsonObject arguments)
      : super(command: 'runInTerminal', arguments: arguments);

  factory DapRunInTerminalProposal.fromArguments(
    Map<String, Object?> arguments,
  ) {
    final validated = _validateArguments(
      'runInTerminal',
      'RunInTerminalRequestArguments',
      arguments,
    );
    final cwd = validated['cwd']! as String;
    final argv = (validated['args']! as List<Object?>).cast<String>();
    final environment = validated['env'];
    if (_containsNul(cwd) ||
        argv.any(_containsNul) ||
        environment is Map<String, Object?> &&
            environment.entries.any(
              (entry) =>
                  _containsNul(entry.key) ||
                  entry.value is String && _containsNul(entry.value! as String),
            )) {
      throw const DapProposalException(
        'dap_terminal_nul_rejected',
        'DAP runInTerminal arguments cannot contain NUL.',
        command: 'runInTerminal',
      );
    }
    final totalLength =
        cwd.length + argv.fold<int>(0, (sum, value) => sum + value.length);
    if (argv.length > 4096 || totalLength > 65536) {
      throw const DapProposalException(
        'dap_terminal_arguments_too_large',
        'DAP runInTerminal arguments exceed the configured limit.',
        command: 'runInTerminal',
      );
    }
    return DapRunInTerminalProposal._(validated);
  }

  String get cwd => arguments['cwd']! as String;
  List<String> get argv => List<String>.unmodifiable(
        (arguments['args']! as List<Object?>).cast<String>(),
      );
  JsonObject get environment =>
      arguments['env'] as JsonObject? ?? const <String, Object?>{};

  /// Deliberately absent: callers receive argv, never a joined shell string.
  String? get shellCommand => null;
}

final class DapStartDebuggingProposal extends DapProposal {
  DapStartDebuggingProposal._(JsonObject arguments)
      : super(command: 'startDebugging', arguments: arguments);

  factory DapStartDebuggingProposal.fromArguments(
    Map<String, Object?> arguments,
  ) =>
      DapStartDebuggingProposal._(
        _validateArguments(
          'startDebugging',
          'StartDebuggingRequestArguments',
          arguments,
        ),
      );

  JsonObject get configuration => arguments['configuration']! as JsonObject;
  String get request => arguments['request']! as String;
}

typedef DapProposalHandler = FutureOr<JsonValue> Function(
  DapProposal proposal,
);

final class DapProposalDispatcher {
  final Map<String, DapProposalHandler> _handlers =
      <String, DapProposalHandler>{};

  void register(String command, DapProposalHandler handler) {
    if (!_proposalCommands.contains(command)) {
      throw DapProposalException(
        'dap_proposal_command_unknown',
        'DAP command has no typed proposal boundary.',
        command: command,
      );
    }
    if (_handlers.containsKey(command)) {
      throw DapProposalException(
        'dap_proposal_handler_duplicate',
        'DAP proposal handler is already registered.',
        command: command,
      );
    }
    _handlers[command] = handler;
  }

  FutureOr<JsonValue> dispatch(
    String command,
    Map<String, Object?> arguments,
  ) {
    final handler = _handlers[command];
    if (handler == null) {
      throw DapProposalException(
        'dap_proposal_handler_missing',
        'No caller handler accepts this DAP proposal.',
        command: command,
      );
    }
    final proposal = switch (command) {
      'runInTerminal' => DapRunInTerminalProposal.fromArguments(arguments),
      'startDebugging' => DapStartDebuggingProposal.fromArguments(arguments),
      _ => throw DapProposalException(
          'dap_proposal_command_unknown',
          'DAP command has no typed proposal boundary.',
          command: command,
        ),
    };
    return handler(proposal);
  }
}

const _proposalCommands = <String>{
  'runInTerminal',
  'startDebugging',
};

JsonObject _validateArguments(
  String command,
  String definition,
  Map<String, Object?> arguments,
) {
  try {
    return DapModelRegistry.instance.validateNamed(
      definition,
      arguments,
    )! as JsonObject;
  } on DapSchemaException catch (error) {
    throw DapProposalException(
      'dap_proposal_schema_invalid',
      'DAP proposal arguments do not satisfy the pinned schema.',
      command: command,
      cause: error,
    );
  }
}

bool _containsNul(String value) => value.contains('\u0000');
