import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  test('computer_20241022 args + id/name', () {
    final t = computer_20241022(
      displayWidthPx: 1024,
      displayHeightPx: 768,
      displayNumber: 1,
    );
    expect(t, isA<ProviderTool>());
    expect(t.id, 'anthropic.computer_20241022');
    expect(t.name, 'computer');
    expect(t.args, {
      'displayWidthPx': 1024,
      'displayHeightPx': 768,
      'displayNumber': 1,
    });
  });

  test('computer_20241022 省略 displayNumber', () {
    final t = computer_20241022(displayWidthPx: 800, displayHeightPx: 600);
    expect(t.args, {'displayWidthPx': 800, 'displayHeightPx': 600});
  });

  test('computer_20250124 id 正确', () {
    expect(
      computer_20250124(displayWidthPx: 1, displayHeightPx: 1).id,
      'anthropic.computer_20250124',
    );
  });

  test('computer_20251124 含 enableZoom', () {
    final t = computer_20251124(
      displayWidthPx: 1,
      displayHeightPx: 1,
      enableZoom: true,
    );
    expect(t.id, 'anthropic.computer_20251124');
    expect(t.args['enableZoom'], true);
  });

  test('computer_20251124 省略 enableZoom 不写键', () {
    final t = computer_20251124(displayWidthPx: 1, displayHeightPx: 1);
    expect(t.args.containsKey('enableZoom'), isFalse);
  });
}
