import 'package:pigcode_ai_openai_compatible/pigcode_ai_openai_compatible.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('MetadataExtractor', () {
    test('可按契约签名构造自定义 extractor 并调用各函数字段', () async {
      final extractor = MetadataExtractor(
        extractMetadata: (parsedBody) async {
          final body = parsedBody as JsonObject;
          return <String, JsonObject>{
            'myProvider': <String, Object?>{'id': body['id']},
          };
        },
        createStreamExtractor: () {
          final chunks = <JsonValue>[];
          return StreamMetadataExtractor(
            processChunk: chunks.add,
            buildMetadata: () => chunks.isEmpty
                ? null
                : <String, JsonObject>{
                    'myProvider': <String, Object?>{
                      'chunkCount': chunks.length
                    },
                  },
          );
        },
      );

      final metadata = await extractor.extractMetadata(
        <String, Object?>{'id': 'resp_1'},
      );
      expect(metadata, {
        'myProvider': {'id': 'resp_1'},
      });

      final streamExtractor = extractor.createStreamExtractor();
      streamExtractor.processChunk(<String, Object?>{'delta': 'a'});
      streamExtractor.processChunk(<String, Object?>{'delta': 'b'});
      final streamMetadata = streamExtractor.buildMetadata();
      expect(streamMetadata, {
        'myProvider': {'chunkCount': 2},
      });
    });

    test('每次调用 createStreamExtractor 都产出独立状态的新实例', () {
      var callCount = 0;
      final extractor = MetadataExtractor(
        extractMetadata: (_) async => null,
        createStreamExtractor: () {
          callCount++;
          final chunks = <JsonValue>[];
          return StreamMetadataExtractor(
            processChunk: chunks.add,
            buildMetadata: () => <String, JsonObject>{
              'p': <String, Object?>{'n': chunks.length}
            },
          );
        },
      );

      final first = extractor.createStreamExtractor();
      first.processChunk(<String, Object?>{});
      first.processChunk(<String, Object?>{});

      final second = extractor.createStreamExtractor();
      second.processChunk(<String, Object?>{});

      expect(callCount, 2);
      expect(first.buildMetadata(), {
        'p': {'n': 2},
      });
      expect(second.buildMetadata(), {
        'p': {'n': 1},
      });
    });
  });
}
