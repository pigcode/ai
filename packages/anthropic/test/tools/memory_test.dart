import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('memory_20250818 id/name + args 空', () {
    final t = memory_20250818();
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.memory_20250818');
    expect(t.name, 'memory');
    expect(t.args, <String, Object?>{});
  });
}
