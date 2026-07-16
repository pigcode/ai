import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('webSearch_20250305 缺省 args 为空 map,id/name 正确', () {
    final tool = webSearch_20250305();
    expect(tool, isA<ProviderTool>());
    expect(tool.id, 'anthropic.web_search_20250305');
    expect(tool.name, 'web_search');
    expect(tool.args, isEmpty);
  });

  test('webSearch_20260209 全参 args 为 camelCase 且省略 null', () {
    final tool = webSearch_20260209(
      maxUses: 3,
      allowedDomains: ['a.com'],
      blockedDomains: ['b.com'],
      userLocation: const AnthropicWebSearchUserLocation(
        city: 'SF',
        timezone: 'America/Los_Angeles',
      ),
    );
    expect(tool.id, 'anthropic.web_search_20260209');
    expect(tool.args, {
      'maxUses': 3,
      'allowedDomains': ['a.com'],
      'blockedDomains': ['b.com'],
      'userLocation': {
        'type': 'approximate', // 固定字面量(报告 07 §1.2 :44)
        'city': 'SF',
        'timezone': 'America/Los_Angeles',
      },
    });
  });
}
