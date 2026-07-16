import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:test/test.dart';

/// 9 工厂 provider 工具自动续接标注断言(上游标注清单:web-search :129
/// ×2 / web-fetch :138 ×2 / tool-search regex :79 / bm25 :67 / advisor
/// :123 / code-execution 20250825 :274 / 20260120 :308);反例:20250522
/// 与 memory 不标(上游零命中,默认 false)。
void main() {
  test('9 个 deferred-capable 工厂标注 supportsDeferredResults=true', () {
    expect(webSearch_20250305().supportsDeferredResults, isTrue);
    expect(webSearch_20260209().supportsDeferredResults, isTrue);
    expect(webFetch_20250910().supportsDeferredResults, isTrue);
    expect(webFetch_20260209().supportsDeferredResults, isTrue);
    expect(toolSearchRegex_20251119().supportsDeferredResults, isTrue);
    expect(toolSearchBm25_20251119().supportsDeferredResults, isTrue);
    expect(
      advisor_20260301(model: 'claude-opus-4-7').supportsDeferredResults,
      isTrue,
    );
    expect(codeExecution_20250825().supportsDeferredResults, isTrue);
    expect(codeExecution_20260120().supportsDeferredResults, isTrue);
  });

  test('codeExecution_20250522 与 memory_20250818 不标(默认 false)', () {
    expect(codeExecution_20250522().supportsDeferredResults, isFalse);
    expect(memory_20250818().supportsDeferredResults, isFalse);
  });
}
