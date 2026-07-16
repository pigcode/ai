import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('toolSearchRegex_20251119:id 段无中间 tool,name 才带 + args 空', () {
    final t = toolSearchRegex_20251119();
    expect(t, isA<ProviderTool>());
    // id 段是 tool_search_regex(无中间 tool);wire name 才是
    // tool_search_tool_regex(报告 09 §1.5,勿混淆)。
    expect(t.id, 'anthropic.tool_search_regex_20251119');
    expect(t.name, 'tool_search_tool_regex');
    expect(t.args, <String, Object?>{});
  });

  test('toolSearchBm25_20251119:id 段无中间 tool,name 才带 + args 空', () {
    final t = toolSearchBm25_20251119();
    expect(t.id, 'anthropic.tool_search_bm25_20251119');
    expect(t.name, 'tool_search_tool_bm25');
    expect(t.args, <String, Object?>{});
  });
}
