import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai/src/prompt/standardize_prompt.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('standardizePrompt', () {
    test('string prompt 归一为单条 user 消息', () {
      final result = standardizePrompt(prompt: '你好');

      expect(result.messages, hasLength(1));
      final message = result.messages.single;
      expect(message, isA<UserModelMessage>());
      final userMessage = message as UserModelMessage;
      expect(userMessage.content, hasLength(1));
      expect((userMessage.content.single as TextPart).text, '你好');
      expect(result.instructions, isNull);
    });

    test('messages 原样透传', () {
      final messages = <ModelMessage>[
        UserModelMessage.text('第一条'),
        AssistantModelMessage.text('回复'),
      ];

      final result = standardizePrompt(messages: messages);

      expect(result.messages, same(messages));
    });

    test('instructions 归一为系统级指令', () {
      final result = standardizePrompt(prompt: '你好', instructions: '你是助手');

      expect(result.instructions, '你是助手');
    });

    test('prompt 与 messages 都缺失时抛 InvalidPromptError', () {
      expect(
        () => standardizePrompt(),
        throwsA(isA<provider.InvalidPromptError>()),
      );
    });

    test('prompt 与 messages 同时提供时抛 InvalidPromptError', () {
      expect(
        () => standardizePrompt(
          prompt: '你好',
          messages: <ModelMessage>[UserModelMessage.text('也好')],
        ),
        throwsA(isA<provider.InvalidPromptError>()),
      );
    });

    test('messages 为空列表时抛 InvalidPromptError', () {
      expect(
        () => standardizePrompt(messages: <ModelMessage>[]),
        throwsA(isA<provider.InvalidPromptError>()),
      );
    });

    test('messages 中含 system 消息时抛 InvalidPromptError', () {
      expect(
        () => standardizePrompt(
          messages: <ModelMessage>[
            const SystemModelMessage('系统提示'),
            UserModelMessage.text('你好'),
          ],
        ),
        throwsA(isA<provider.InvalidPromptError>()),
      );
    });
  });
}
