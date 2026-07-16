import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('advisor_20260301 仅 model 时 args 恰为 {model}(maxUses/caching 键缺席)', () {
    final t = advisor_20260301(model: 'claude-opus-4-7');
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.advisor_20260301');
    expect(t.name, 'advisor');
    expect(t.args, {'model': 'claude-opus-4-7'});
  });

  test('advisor_20260301 全参 args 为 camelCase 且 caching 内联为 toJson 结果', () {
    final tool = advisor_20260301(
      model: 'claude-opus-4-7',
      maxUses: 5,
      caching: const AnthropicAdvisorCaching(ttl: '5m'),
    );
    expect(tool.id, 'anthropic.advisor_20260301');
    expect(tool.args, {
      'model': 'claude-opus-4-7',
      'maxUses': 5,
      'caching': {'type': 'ephemeral', 'ttl': '5m'},
    });
  });

  test('AnthropicAdvisorCaching.toJson() 恒 type=ephemeral,ttl 原样透传', () {
    expect(
      const AnthropicAdvisorCaching(ttl: '5m').toJson(),
      {'type': 'ephemeral', 'ttl': '5m'},
    );
    expect(
      const AnthropicAdvisorCaching(ttl: '1h').toJson(),
      {'type': 'ephemeral', 'ttl': '1h'},
    );
  });
}
