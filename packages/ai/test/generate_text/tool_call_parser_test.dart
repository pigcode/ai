import 'package:pigcode_ai/src/generate_text/tool_call_parser.dart';
import 'package:pigcode_ai/src/generate_text/tool_call_repair.dart';
import 'package:pigcode_ai/src/tool/tool.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('provider 工具跳过 schema 校验,透传解析后的 input', () {
    final tools = <String, Tool>{
      'computer': Tool.provider(
        const ProviderTool(
          id: 'anthropic.computer_20250124',
          name: 'computer',
          args: {},
        ),
        execute: (i, o) async => null,
      ),
    };
    // 任意 input(即使不符任何 schema)都不应抛 InvalidToolInputError。
    final parsed = parseToolCall(
      toolCall: const ToolCall(
          toolCallId: 'c1',
          toolName: 'computer',
          input: '{"action":"screenshot"}'),
      tools: tools,
    );
    expect(parsed.input, {'action': 'screenshot'});
  });

  test('provider 工具的 input JSON 非法仍抛 InvalidToolInputError(JSON parse 不变)', () {
    final tools = <String, Tool>{
      'computer': Tool.provider(
        const ProviderTool(
          id: 'anthropic.computer_20250124',
          name: 'computer',
          args: {},
        ),
      ),
    };
    expect(
      () => parseToolCall(
        toolCall: const ToolCall(
            toolCallId: 'c1', toolName: 'computer', input: '{not json'),
        tools: tools,
      ),
      throwsA(isA<InvalidToolInputError>()),
    );
  });
}
