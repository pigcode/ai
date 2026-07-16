import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';
import 'package:test/test.dart';

void main() {
  group('single call full lifecycle', () {
    test('start -> delta -> detects completion -> end + call', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'get_weather',
        argumentsDelta: '{"ci',
      );
      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'get_weather'),
            const ToolInputDelta('call_1', '{"ci'),
          ]));

      final e2 = tracker.addDelta(index: 0, argumentsDelta: 'ty": "SF"}');
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', 'ty": "SF"}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: '{"city": "SF"}',
            ),
          ]));

      // 完成后 finishAll 不应重复补发。
      expect(tracker.finishAll(), isEmpty);
    });

    test('first chunk already contains full valid JSON finishes immediately',
        () {
      final tracker = StreamingToolCallTracker();

      final events = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'get_weather',
        argumentsDelta: '{"city": "London"}',
      );

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'get_weather'),
            const ToolInputDelta('call_1', '{"city": "London"}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: '{"city": "London"}',
            ),
          ]));
    });
  });

  group('multiple interleaved calls', () {
    test('deltas for two different indices interleave without cross-talk', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'get_weather',
        argumentsDelta: '{"ci',
      );
      final e2 = tracker.addDelta(
        index: 1,
        id: 'call_2',
        name: 'get_time',
        argumentsDelta: '{"tz',
      );
      final e3 = tracker.addDelta(index: 0, argumentsDelta: 'ty": "NYC"}');
      final e4 = tracker.addDelta(index: 1, argumentsDelta: '": "UTC"}');

      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'get_weather'),
            const ToolInputDelta('call_1', '{"ci'),
          ]));
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_2', toolName: 'get_time'),
            const ToolInputDelta('call_2', '{"tz'),
          ]));
      expect(
          e3,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', 'ty": "NYC"}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'get_weather',
              input: '{"city": "NYC"}',
            ),
          ]));
      expect(
          e4,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_2', '": "UTC"}'),
            const ToolInputEnd('call_2'),
            const ToolCall(
              toolCallId: 'call_2',
              toolName: 'get_time',
              input: '{"tz": "UTC"}',
            ),
          ]));
    });
  });

  group('index defaults to sequential increment', () {
    test('omitting index falls back to arrival-order sequential counting', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(id: 'call_1', name: 'first');
      final e2 = tracker.addDelta(id: 'call_2', name: 'second');

      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'first'),
          ]));
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_2', toolName: 'second'),
          ]));

      // 后续用显式 index=0 追加应命中第一个调用（顺序计数与显式 index 共享同一映射）。
      final e3 = tracker.addDelta(index: 0, argumentsDelta: '{}');
      expect(
          e3,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', '{}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
                toolCallId: 'call_1', toolName: 'first', input: '{}'),
          ]));
    });

    test('explicit high index then omitted index continues after it', () {
      final tracker = StreamingToolCallTracker();

      tracker.addDelta(
        index: 5,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '1',
      );
      final e2 = tracker.addDelta(id: 'call_2', name: 'fn2');

      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_2', toolName: 'fn2'),
          ]));
    });
  });

  group('missing id/name on first chunk throws', () {
    test('missing id throws InvalidResponseDataError', () {
      final tracker = StreamingToolCallTracker();

      expect(
        () => tracker.addDelta(index: 0, name: 'fn'),
        throwsA(isA<InvalidResponseDataError>()),
      );
    });

    test('missing name throws InvalidResponseDataError', () {
      final tracker = StreamingToolCallTracker();

      expect(
        () => tracker.addDelta(index: 0, id: 'call_1'),
        throwsA(isA<InvalidResponseDataError>()),
      );
    });

    test('missing both id and name throws InvalidResponseDataError', () {
      final tracker = StreamingToolCallTracker();

      expect(
        () => tracker.addDelta(index: 0),
        throwsA(isA<InvalidResponseDataError>()),
      );
    });
  });

  group('isParsableJson probing boundaries', () {
    test('empty object arguments is parsable and finishes on first chunk', () {
      final tracker = StreamingToolCallTracker();

      final events = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '{}',
      );

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', '{}'),
            const ToolInputEnd('call_1'),
            const ToolCall(toolCallId: 'call_1', toolName: 'fn', input: '{}'),
          ]));
    });

    test(
        'no arguments on first chunk does not finish (empty string unparsable)',
        () {
      final tracker = StreamingToolCallTracker();

      final events = tracker.addDelta(index: 0, id: 'call_1', name: 'fn');

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
          ]));
    });

    test('nested JSON only becomes parsable once fully closed', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '{"a":{"b":1',
      );
      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', '{"a":{"b":1'),
          ]));

      final e2 = tracker.addDelta(index: 0, argumentsDelta: '}');
      // 内层对象闭合但外层未闭合，仍不可解析。
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', '}'),
          ]));

      final e3 = tracker.addDelta(index: 0, argumentsDelta: '}');
      expect(
          e3,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', '}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'fn',
              input: '{"a":{"b":1}}',
            ),
          ]));
    });
  });

  group('finishAll flushes unfinished calls ascending by index', () {
    test('flush emits end + call for unfinished calls sorted by index', () {
      final tracker = StreamingToolCallTracker();

      tracker.addDelta(
        index: 2,
        id: 'call_3',
        name: 'third',
        argumentsDelta: '{"x":1',
      );
      tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'first',
        argumentsDelta: '{"y":2',
      );
      tracker.addDelta(
        index: 1,
        id: 'call_2',
        name: 'second',
        argumentsDelta: '{"z":3',
      );

      final events = tracker.finishAll();

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'first',
              input: '{"y":2',
            ),
            const ToolInputEnd('call_2'),
            const ToolCall(
              toolCallId: 'call_2',
              toolName: 'second',
              input: '{"z":3',
            ),
            const ToolInputEnd('call_3'),
            const ToolCall(
              toolCallId: 'call_3',
              toolName: 'third',
              input: '{"x":1',
            ),
          ]));
    });

    test('flush does not re-emit already-finished calls', () {
      final tracker = StreamingToolCallTracker();

      tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '{}',
      );
      // call_1 已在 addDelta 内完成。

      tracker.addDelta(
        index: 1,
        id: 'call_2',
        name: 'fn2',
        argumentsDelta: '{"a":1',
      );

      final events = tracker.finishAll();

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputEnd('call_2'),
            const ToolCall(
              toolCallId: 'call_2',
              toolName: 'fn2',
              input: '{"a":1',
            ),
          ]));
    });

    test('finishAll on tracker with no calls returns empty list', () {
      final tracker = StreamingToolCallTracker();
      expect(tracker.finishAll(), isEmpty);
    });
  });

  group('chunks arriving after completion on the same index', () {
    test('further deltas on an already-finished index are ignored', () {
      final tracker = StreamingToolCallTracker();

      tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '{}',
      );
      final events = tracker.addDelta(index: 0, argumentsDelta: 'garbage');

      expect(events, isEmpty);

      // finishAll 不应因为忽略的分片重新产出事件。
      expect(tracker.finishAll(), isEmpty);
    });
  });

  group('scalar arguments must not finalize early', () {
    // 数学依据：append-only 流下，对象/数组一旦可解析即已完整（再追加必
    // 非法闭合），但数字标量可解析后仍可能继续增长（如 '1' 后接 '23' 变
    // 成 '123'，两者都是合法 JSON）。因此提前定稿探测必须以累积
    // arguments trimLeft 后首字符是否为 '{' 或 '[' 为前提，数字/字符串/
    // 布尔/null 前缀一律不提前定稿，留给 finishAll() 收尾。
    test(
        'numeric scalar split across two parsable-looking chunks does not '
        'finish early; only ToolInputDelta is emitted each time', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'set_count',
        argumentsDelta: '1',
      );
      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'set_count'),
            const ToolInputDelta('call_1', '1'),
          ]));

      final e2 = tracker.addDelta(index: 0, argumentsDelta: '23');
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', '23'),
          ]));

      final events = tracker.finishAll();
      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'set_count',
              input: '123',
            ),
          ]));
    });

    test(
        'object arguments still finish immediately once parsable (early '
        'finalization timing unchanged for object/array prefixes)', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '{"a":',
      );
      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', '{"a":'),
          ]));

      // 第二个 delta 后应立即追加 ToolInputEnd + ToolCall（提前定稿时序
      // 不变），不等待 finishAll()。
      final e2 = tracker.addDelta(index: 0, argumentsDelta: '1}');
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', '1}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'fn',
              input: '{"a":1}',
            ),
          ]));
    });

    test('leading whitespace before object is still recognized as object', () {
      final tracker = StreamingToolCallTracker();

      final events = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '  {"a":1}',
      );

      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', '  {"a":1}'),
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'fn',
              input: '  {"a":1}',
            ),
          ]));
    });

    test('bare string scalar does not finish early, finishAll flushes it', () {
      final tracker = StreamingToolCallTracker();

      final e1 = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: '"hel',
      );
      expect(
          e1,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', '"hel'),
          ]));

      final e2 = tracker.addDelta(index: 0, argumentsDelta: 'lo"');
      // '"hello"' 可解析为合法 JSON 字符串，但字符串前缀不提前定稿。
      expect(
          e2,
          equals(<LanguageModelStreamPart>[
            const ToolInputDelta('call_1', 'lo"'),
          ]));

      expect(
          tracker.finishAll(),
          equals(<LanguageModelStreamPart>[
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'fn',
              input: '"hello"',
            ),
          ]));
    });

    test('bare boolean/null scalar does not finish early', () {
      final tracker = StreamingToolCallTracker();

      final events = tracker.addDelta(
        index: 0,
        id: 'call_1',
        name: 'fn',
        argumentsDelta: 'true',
      );

      // 'true' 整体已可解析，但布尔前缀不提前定稿。
      expect(
          events,
          equals(<LanguageModelStreamPart>[
            const ToolInputStart(id: 'call_1', toolName: 'fn'),
            const ToolInputDelta('call_1', 'true'),
          ]));

      expect(
          tracker.finishAll(),
          equals(<LanguageModelStreamPart>[
            const ToolInputEnd('call_1'),
            const ToolCall(
              toolCallId: 'call_1',
              toolName: 'fn',
              input: 'true',
            ),
          ]));
    });
  });
}
