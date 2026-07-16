import 'package:pigcode_ai/src/prompt/content_part.dart';
import 'package:pigcode_ai/src/prompt/from_language_model_prompt.dart';
import 'package:pigcode_ai/src/prompt/model_message.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

void main() {
  group('convertFromLanguageModelPrompt', () {
    test('maps provider.FileDataText back to DataText', () {
      final result = convertFromLanguageModelPrompt(
        const [
          provider.UserMessage([
            provider.FilePart(
              data: provider.FileDataText('plain document'),
              mediaType: 'text/plain',
            ),
          ]),
        ],
      );

      final user = result.single as UserModelMessage;
      final filePart = user.content.single as FilePart;
      expect(filePart.data, const DataText('plain document'));
      expect(filePart.mediaType, 'text/plain');
    });
  });
}
