import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('textEditor_20241022 id/name + args 空', () {
    final t = textEditor_20241022();
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.text_editor_20241022');
    expect(t.name, 'str_replace_editor');
    expect(t.args, <String, Object?>{});
  });

  test('textEditor_20250124 id/name', () {
    final t = textEditor_20250124();
    expect(t.id, 'anthropic.text_editor_20250124');
    expect(t.name, 'str_replace_editor');
    expect(t.args, <String, Object?>{});
  });

  test('textEditor_20250728 id/name + maxCharacters', () {
    final t = textEditor_20250728(maxCharacters: 5000);
    expect(t.id, 'anthropic.text_editor_20250728');
    expect(t.name, 'str_replace_based_edit_tool');
    expect(t.args, {'maxCharacters': 5000});
  });

  test('textEditor_20250728 省略 maxCharacters 时 args 空', () {
    final t = textEditor_20250728();
    expect(t.args, <String, Object?>{});
  });
}
