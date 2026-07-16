import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:test/test.dart';

void main() {
  group('getOpenAiCompatibleResponseMetadata', () {
    test('三字段齐全时全部提取', () {
      final metadata = getOpenAiCompatibleResponseMetadata(<String, Object?>{
        'id': 'chatcmpl-123',
        'model': 'glm-4',
        'created': 1700000000,
      });

      expect(metadata.id, 'chatcmpl-123');
      expect(metadata.modelId, 'glm-4');
      expect(
        metadata.timestamp,
        DateTime.fromMillisecondsSinceEpoch(1700000000 * 1000),
      );
    });

    test('三字段全部缺失时全部为 null', () {
      final metadata = getOpenAiCompatibleResponseMetadata(<String, Object?>{});

      expect(metadata.id, isNull);
      expect(metadata.modelId, isNull);
      expect(metadata.timestamp, isNull);
    });

    test('created 为 0 时仍产出 timestamp(!= null 判空,对齐 raw 本身)', () {
      final metadata = getOpenAiCompatibleResponseMetadata(<String, Object?>{
        'created': 0,
      });

      expect(metadata.timestamp, DateTime.fromMillisecondsSinceEpoch(0));
    });
  });
}
