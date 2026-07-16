import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('bash_20241022 id/name + args 空', () {
    final t = bash_20241022();
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.bash_20241022');
    expect(t.name, 'bash');
    expect(t.args, <String, Object?>{});
  });

  test('bash_20250124 id/name + args 空', () {
    final t = bash_20250124();
    expect(t.id, 'anthropic.bash_20250124');
    expect(t.name, 'bash');
    expect(t.args, <String, Object?>{});
  });

  group('anthropicTools 聚合入口与顶层函数委托一致(8 方法)', () {
    test('computer_20241022', () {
      expect(
        anthropicTools.computer_20241022(
          displayWidthPx: 1024,
          displayHeightPx: 768,
        ),
        computer_20241022(displayWidthPx: 1024, displayHeightPx: 768),
      );
    });

    test('computer_20250124', () {
      expect(
        anthropicTools.computer_20250124(
          displayWidthPx: 1024,
          displayHeightPx: 768,
        ),
        computer_20250124(displayWidthPx: 1024, displayHeightPx: 768),
      );
    });

    test('computer_20251124', () {
      expect(
        anthropicTools.computer_20251124(
          displayWidthPx: 1024,
          displayHeightPx: 768,
        ),
        computer_20251124(displayWidthPx: 1024, displayHeightPx: 768),
      );
    });

    test('textEditor_20241022', () {
      expect(
        anthropicTools.textEditor_20241022(),
        textEditor_20241022(),
      );
    });

    test('textEditor_20250124', () {
      expect(
        anthropicTools.textEditor_20250124(),
        textEditor_20250124(),
      );
    });

    test('textEditor_20250728', () {
      expect(
        anthropicTools.textEditor_20250728(maxCharacters: 5000),
        textEditor_20250728(maxCharacters: 5000),
      );
    });

    test('bash_20241022', () {
      expect(anthropicTools.bash_20241022(), bash_20241022());
    });

    test('bash_20250124', () {
      expect(anthropicTools.bash_20250124(), bash_20250124());
    });
  });
}
