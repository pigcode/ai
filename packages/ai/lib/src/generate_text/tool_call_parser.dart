import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

import '../prompt/from_language_model_prompt.dart';
import '../tool/tool.dart';
import 'tool_call_repair.dart';

/// 已解析且已匹配到工具定义的工具调用。
final class ParsedToolCall {
  /// 创建已解析工具调用。
  const ParsedToolCall({
    required this.toolCall,
    required this.input,
  });

  /// 原始或修复后的工具调用。
  final provider.ToolCall toolCall;

  /// 已解析并通过 schema 校验的工具入参。
  final provider.JsonValue input;
}

/// 解析工具调用,必要时调用 [repairToolCall] 修复后再解析一次。
Future<ParsedToolCall> parseOrRepairToolCall({
  required provider.ToolCall toolCall,
  required ToolSet? tools,
  required ToolCallRepairFunction? repairToolCall,
  required String? instructions,
  required Iterable<provider.LanguageModelMessage> messages,
}) async {
  try {
    return parseToolCall(toolCall: toolCall, tools: tools);
  } on ToolCallRepairFailure catch (error) {
    if (repairToolCall == null) {
      rethrow;
    }

    final toolSet = tools == null
        ? const <String, Tool>{}
        : Map<String, Tool>.unmodifiable(tools);
    final repairedToolCall = await _repairToolCall(
      repairToolCall: repairToolCall,
      instructions: instructions,
      messages: messages,
      toolCall: toolCall,
      tools: toolSet,
      error: error,
    );
    if (repairedToolCall == null) {
      rethrow;
    }
    return parseToolCall(toolCall: repairedToolCall, tools: tools);
  }
}

/// 解析工具调用输入并按工具 schema 校验。
ParsedToolCall parseToolCall({
  required provider.ToolCall toolCall,
  required ToolSet? tools,
}) {
  final tool = tools?[toolCall.toolName];
  if (tool == null) {
    throw NoSuchToolError(
      toolName: toolCall.toolName,
      availableTools: tools?.keys.toList(growable: false) ?? const [],
    );
  }

  final input = _parseToolInput(toolCall);
  final parsedToolCall = toolCall.input.trim().isEmpty
      ? provider.ToolCall(
          toolCallId: toolCall.toolCallId,
          toolName: toolCall.toolName,
          input: '{}',
          providerExecuted: toolCall.providerExecuted,
          isDynamic: toolCall.isDynamic,
          providerMetadata: toolCall.providerMetadata,
        )
      : toolCall;
  // provider 定义工具(inputSchema 恒为 null)透传原始 input,跳过 schema
  // 校验;JSON parse 语义(上方 `_parseToolInput`)不变。
  if (tool.inputSchema case final schema?) {
    try {
      validateTypes(input, JsonSchemaValidator.fromContract(schema));
    } on provider.TypeValidationError catch (error) {
      throw InvalidToolInputError(
        toolName: toolCall.toolName,
        toolInput: toolCall.input,
        cause: error,
      );
    }
  }
  return ParsedToolCall(toolCall: parsedToolCall, input: input);
}

Future<provider.ToolCall?> _repairToolCall({
  required ToolCallRepairFunction repairToolCall,
  required String? instructions,
  required Iterable<provider.LanguageModelMessage> messages,
  required provider.ToolCall toolCall,
  required ToolSet tools,
  required ToolCallRepairFailure error,
}) async {
  try {
    return await repairToolCall(ToolCallRepairOptions(
      instructions: instructions,
      messages: convertFromLanguageModelPrompt(
        messages.where((message) => message is! provider.SystemMessage),
      ),
      toolCall: toolCall,
      tools: tools,
      inputSchema: ({required toolName}) => _inputSchema(
        tools: tools,
        toolName: toolName,
      ),
      error: error,
    ));
  } catch (repairError) {
    throw ToolCallRepairError(
      originalError: error,
      cause: repairError,
    );
  }
}

provider.JsonValue _parseToolInput(provider.ToolCall toolCall) {
  if (toolCall.input.trim().isEmpty) {
    return const <String, Object?>{};
  }
  try {
    return parseJson(toolCall.input);
  } on provider.JsonParseError catch (error) {
    throw InvalidToolInputError(
      toolName: toolCall.toolName,
      toolInput: toolCall.input,
      cause: error,
    );
  }
}

provider.JsonSchema _inputSchema({
  required ToolSet tools,
  required String toolName,
}) {
  final tool = tools[toolName];
  if (tool == null) {
    throw NoSuchToolError(
      toolName: toolName,
      availableTools: tools.keys.toList(growable: false),
    );
  }
  final schema = tool.inputSchema;
  if (schema == null) {
    // provider 定义工具无 inputSchema;修复流程(ToolCallRepairOptions.
    // inputSchema)不适用于此类工具。
    throw StateError(
      'provider tool "$toolName" has no input schema; repair not applicable',
    );
  }
  return schema;
}
