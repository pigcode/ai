import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('webFetch_20250910 缺省 args 为空 map,id/name 正确', () {
    final tool = webFetch_20250910();
    expect(tool, isA<ProviderTool>());
    expect(tool.id, 'anthropic.web_fetch_20250910');
    expect(tool.name, 'web_fetch');
    expect(tool.args, isEmpty);
  });

  test('webFetch_20260209 全参 args 为 camelCase 且省略 null', () {
    final tool = webFetch_20260209(
      maxUses: 2,
      allowedDomains: ['a.com'],
      blockedDomains: ['b.com'],
      citations: const AnthropicWebFetchCitations(enabled: true),
      maxContentTokens: 4096,
    );
    expect(tool.id, 'anthropic.web_fetch_20260209');
    expect(tool.args, {
      'maxUses': 2,
      'allowedDomains': ['a.com'],
      'blockedDomains': ['b.com'],
      'citations': {'enabled': true},
      'maxContentTokens': 4096,
    });
  });

  group('anthropicTools 聚合入口与顶层函数委托一致', () {
    test('webSearch_20250305', () {
      expect(
        anthropicTools.webSearch_20250305(maxUses: 1),
        webSearch_20250305(maxUses: 1),
      );
    });

    test('webSearch_20260209', () {
      expect(
        anthropicTools.webSearch_20260209(maxUses: 1),
        webSearch_20260209(maxUses: 1),
      );
    });

    test('webFetch_20250910', () {
      expect(
        anthropicTools.webFetch_20250910(maxUses: 2),
        webFetch_20250910(maxUses: 2),
      );
    });

    test('webFetch_20260209', () {
      expect(
        anthropicTools.webFetch_20260209(maxUses: 2),
        webFetch_20260209(maxUses: 2),
      );
    });
  });
}
