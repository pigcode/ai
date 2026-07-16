import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('SystemModelMessage', () {
    test('holds string content', () {
      const message = SystemModelMessage('you are a helpful assistant');

      expect(message.content, 'you are a helpful assistant');
      expect(message.providerOptions, isNull);
    });

    test('equality by content and providerOptions', () {
      const a = SystemModelMessage('sys', providerOptions: {'openai': {}});
      const b = SystemModelMessage('sys', providerOptions: {'openai': {}});
      const c = SystemModelMessage('other');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('UserModelMessage', () {
    test('holds a list of user content parts', () {
      const message = UserModelMessage([TextPart('hello')]);

      expect(message.content, [const TextPart('hello')]);
    });

    test('.text() factory builds a single TextPart', () {
      final message = UserModelMessage.text('hello');

      expect(message.content, [const TextPart('hello')]);
      expect(message.providerOptions, isNull);
    });

    test('.text() factory forwards providerOptions', () {
      final message =
          UserModelMessage.text('hi', providerOptions: const {'openai': {}});

      expect(message.providerOptions, const {'openai': {}});
    });

    test('equality by content', () {
      final a = UserModelMessage.text('hi');
      final b = UserModelMessage.text('hi');
      final c = UserModelMessage.text('bye');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('AssistantModelMessage', () {
    test('holds a list of assistant content parts', () {
      const message = AssistantModelMessage([TextPart('hi there')]);

      expect(message.content, [const TextPart('hi there')]);
    });

    test('.text() factory builds a single TextPart', () {
      final message = AssistantModelMessage.text('hi there');

      expect(message.content, [const TextPart('hi there')]);
      expect(message.providerOptions, isNull);
    });

    test('equality by content', () {
      final a = AssistantModelMessage.text('hi');
      final b = AssistantModelMessage.text('hi');
      final c = AssistantModelMessage.text('bye');

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ToolModelMessage', () {
    test('holds a list of tool content parts', () {
      const message = ToolModelMessage([
        ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          output: provider.ToolResultText('done'),
        ),
      ]);

      expect(message.content, hasLength(1));
      expect(message.content.single, isA<ToolResultPart>());
    });

    test('equality by content', () {
      const a = ToolModelMessage([
        ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          output: provider.ToolResultText('done'),
        ),
      ]);
      const b = ToolModelMessage([
        ToolResultPart(
          toolCallId: 'call_1',
          toolName: 'lookup',
          output: provider.ToolResultText('done'),
        ),
      ]);
      const c = ToolModelMessage([
        ToolResultPart(
          toolCallId: 'call_2',
          toolName: 'lookup',
          output: provider.ToolResultText('done'),
        ),
      ]);

      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  test('ModelMessage subtypes are not equal across roles with same text', () {
    final user = UserModelMessage.text('same');
    final assistant = AssistantModelMessage.text('same');

    expect(user, isNot(equals(assistant)));
  });
}
