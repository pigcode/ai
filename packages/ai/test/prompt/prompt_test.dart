import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/prompt/prompt.dart';
import 'package:test/test.dart';

void main() {
  group('Prompt', () {
    test('构造:仅 prompt 字符串', () {
      const prompt = Prompt(prompt: '你好');

      expect(prompt.prompt, '你好');
      expect(prompt.messages, isNull);
      expect(prompt.instructions, isNull);
    });

    test('构造:仅 messages 列表', () {
      final messages = [UserModelMessage.text('你好')];
      final prompt = Prompt(messages: messages);

      expect(prompt.prompt, isNull);
      expect(prompt.messages, messages);
    });

    test('构造:prompt 与 messages 可同时为空(类型层不校验,校验留给 standardizePrompt)', () {
      const prompt = Prompt();

      expect(prompt.prompt, isNull);
      expect(prompt.messages, isNull);
    });

    test('构造:prompt 与 messages 可同时非空(类型层不校验,校验留给 standardizePrompt)', () {
      final messages = [AssistantModelMessage.text('嗨')];
      final prompt = Prompt(prompt: '你好', messages: messages);

      expect(prompt.prompt, '你好');
      expect(prompt.messages, messages);
    });

    test('instructions 可单独承载系统级指令', () {
      const prompt = Prompt(instructions: '系统指令');

      expect(prompt.instructions, '系统指令');
    });

    test('相等性:字段全部相同则相等', () {
      final messages = [UserModelMessage.text('你好')];
      final a = Prompt(prompt: 'p', messages: messages, instructions: 'i');
      final b = Prompt(prompt: 'p', messages: messages, instructions: 'i');

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
    });

    test('相等性:任一字段不同则不相等', () {
      const a = Prompt(prompt: 'p1');
      const a2 = Prompt(prompt: 'p2');

      expect(a, isNot(equals(a2)));
    });
  });

  test('Instructions 是 String 的别名', () {
    const Instructions value = '系统指令文本';

    expect(value, isA<String>());
  });
}
