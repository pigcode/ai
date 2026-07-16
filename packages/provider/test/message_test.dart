import 'package:pigcode_ai_provider/src/language_model/content_part.dart';
import 'package:pigcode_ai_provider/src/language_model/message.dart';
import 'package:pigcode_ai_provider/src/language_model/tool.dart';
import 'package:test/test.dart';

void main() {
  group('LanguageModelMessage 四角色构造与角色安全', () {
    test('SystemMessage 承载纯字符串 content', () {
      const msg = SystemMessage('you are helpful');
      expect(msg.content, 'you are helpful');
      expect(msg.providerOptions, isNull);
      expect(msg, isA<LanguageModelMessage>());
    });

    test('UserMessage 承载 UserContentPart 列表', () {
      const msg = UserMessage([TextPart('hi')]);
      expect(msg.content, hasLength(1));
      expect(msg.content.single, isA<UserContentPart>());
      expect(msg, isA<LanguageModelMessage>());
    });

    test('AssistantMessage 承载 AssistantContentPart 列表', () {
      const msg = AssistantMessage([TextPart('answer')]);
      expect(msg.content, hasLength(1));
      expect(msg.content.single, isA<AssistantContentPart>());
    });

    test('ToolMessage 承载 ToolContentPart 列表', () {
      const msg = ToolMessage([
        ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'search',
          output: ToolResultText('done'),
        ),
      ]);
      expect(msg.content, hasLength(1));
      expect(msg.content.single, isA<ToolContentPart>());
    });

    test('providerOptions 可透传', () {
      const msg = SystemMessage('sys', providerOptions: {
        'openai': {'store': true},
      });
      expect(msg.providerOptions, {
        'openai': {'store': true},
      });
    });
  });

  group('值相等(内容列表深比较)', () {
    test('内容列表相等的 UserMessage 相等', () {
      const a = UserMessage([TextPart('hi'), TextPart('there')]);
      const b = UserMessage([TextPart('hi'), TextPart('there')]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('内容列表不同则不相等', () {
      const a = UserMessage([TextPart('hi')]);
      const b = UserMessage([TextPart('bye')]);
      expect(a, isNot(equals(b)));
    });

    test('providerOptions 参与相等比较', () {
      const a = SystemMessage('sys', providerOptions: {
        'openai': {'store': true},
      });
      const b = SystemMessage('sys', providerOptions: {
        'openai': {'store': true},
      });
      const c = SystemMessage('sys');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('不同角色即使载荷同形也不相等', () {
      const user = UserMessage([TextPart('x')]);
      const assistant = AssistantMessage([TextPart('x')]);
      expect(user, isNot(equals(assistant)));
    });

    test('AssistantMessage 内容列表深比较相等', () {
      const a = AssistantMessage([TextPart('a'), TextPart('b')]);
      const b = AssistantMessage([TextPart('a'), TextPart('b')]);
      expect(a, equals(b));
    });
  });

  group('LanguageModelPrompt', () {
    test('一个小 prompt 列表可由异构消息组成', () {
      const LanguageModelPrompt prompt = [
        SystemMessage('you are helpful'),
        UserMessage([TextPart('hello')]),
        AssistantMessage([TextPart('hi, how can I help?')]),
      ];
      expect(prompt, hasLength(3));
      expect(prompt.first, isA<SystemMessage>());
      expect(prompt[1], isA<UserMessage>());
      expect(prompt.last, isA<AssistantMessage>());
    });

    test('内容相等的两个 prompt 列表整体相等', () {
      const LanguageModelPrompt a = [
        SystemMessage('sys'),
        UserMessage([TextPart('hi')]),
      ];
      const LanguageModelPrompt b = [
        SystemMessage('sys'),
        UserMessage([TextPart('hi')]),
      ];
      expect(a, equals(b));
    });
  });
}
