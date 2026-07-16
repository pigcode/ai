import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('codeExecution_20250522 id/name + args 空', () {
    final t = codeExecution_20250522();
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.code_execution_20250522');
    expect(t.name, 'code_execution');
    expect(t.args, <String, Object?>{});
  });

  test('codeExecution_20250825 id/name + args 空', () {
    final t = codeExecution_20250825();
    expect(t.id, 'anthropic.code_execution_20250825');
    expect(t.name, 'code_execution');
    expect(t.args, <String, Object?>{});
  });

  test('codeExecution_20260120 id/name + args 空', () {
    final t = codeExecution_20260120();
    expect(t.id, 'anthropic.code_execution_20260120');
    expect(t.name, 'code_execution');
    expect(t.args, <String, Object?>{});
  });
}
