import 'package:pigcode_ai_openai/pigcode_ai_openai.dart';
import 'package:test/test.dart';

void main() {
  group('getOpenAiChatResponseMetadata', () {
    test('三字段齐全时全部提取', () {
      final metadata = getOpenAiChatResponseMetadata(<String, Object?>{
        'id': 'chatcmpl-123',
        'model': 'gpt-4o',
        'created': 1700000000,
      });

      expect(metadata.id, 'chatcmpl-123');
      expect(metadata.modelId, 'gpt-4o');
      expect(
        metadata.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('三字段全部缺失时全部为 null', () {
      final metadata = getOpenAiChatResponseMetadata(<String, Object?>{});

      expect(metadata.id, isNull);
      expect(metadata.modelId, isNull);
      expect(metadata.timestamp, isNull);
    });

    test('created 为 0 时仍产出 timestamp(!= null 判空,偏离 v7 真值判断)', () {
      final metadata = getOpenAiChatResponseMetadata(<String, Object?>{
        'created': 0,
      });

      expect(metadata.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });

    test('equatable 值相等', () {
      const a = OpenAiChatResponseMetadata(id: 'x');
      const b = OpenAiChatResponseMetadata(id: 'x');

      expect(a, equals(b));
    });
  });
}
