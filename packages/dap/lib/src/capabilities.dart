import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

/// Immutable DAP adapter capability generation.
final class DapCapabilitySnapshot {
  DapCapabilitySnapshot._({
    required this.connectionId,
    required this.generation,
    required this.values,
  });

  factory DapCapabilitySnapshot.fromInitialize({
    required int connectionId,
    required Map<String, Object?> capabilities,
  }) =>
      DapCapabilitySnapshot._(
        connectionId: connectionId,
        generation: 1,
        values: freezeJsonObject(capabilities),
      );

  final int connectionId;
  final int generation;
  final JsonObject values;

  bool supportsCommand(String command) {
    final capability = _commandCapabilities[command];
    return capability == null || values[capability] == true;
  }

  DapCapabilitySnapshot update(Map<String, Object?> changes) {
    return DapCapabilitySnapshot._(
      connectionId: connectionId,
      generation: generation + 1,
      values: freezeJsonObject(<String, Object?>{
        ...values,
        ...changes,
      }),
    );
  }
}

const _commandCapabilities = <String, String>{
  'configurationDone': 'supportsConfigurationDoneRequest',
  'restart': 'supportsRestartRequest',
  'terminate': 'supportsTerminateRequest',
  'breakpointLocations': 'supportsBreakpointLocationsRequest',
  'setFunctionBreakpoints': 'supportsFunctionBreakpoints',
  'dataBreakpointInfo': 'supportsDataBreakpoints',
  'setDataBreakpoints': 'supportsDataBreakpoints',
  'setInstructionBreakpoints': 'supportsInstructionBreakpoints',
  'stepBack': 'supportsStepBack',
  'reverseContinue': 'supportsStepBack',
  'restartFrame': 'supportsRestartFrame',
  'gotoTargets': 'supportsGotoTargetsRequest',
  'goto': 'supportsGotoTargetsRequest',
  'setVariable': 'supportsSetVariable',
  'modules': 'supportsModulesRequest',
  'loadedSources': 'supportsLoadedSourcesRequest',
  'setExpression': 'supportsSetExpression',
  'stepInTargets': 'supportsStepInTargetsRequest',
  'completions': 'supportsCompletionsRequest',
  'exceptionInfo': 'supportsExceptionInfoRequest',
  'readMemory': 'supportsReadMemoryRequest',
  'writeMemory': 'supportsWriteMemoryRequest',
  'disassemble': 'supportsDisassembleRequest',
  'cancel': 'supportsCancelRequest',
  'terminateThreads': 'supportsTerminateThreadsRequest',
};
