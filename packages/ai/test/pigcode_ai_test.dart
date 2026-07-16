// ignore: unused_import
import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  test('pigcode_ai 可解析自身 barrel 与 pigcode_ai_provider 契约依赖', () {
    // 目前 barrel 为空;本用例仅验证包身份与契约层依赖可解析、可按前缀 import。
    expect(provider.InvalidPromptError, isNotNull);
  });
}
