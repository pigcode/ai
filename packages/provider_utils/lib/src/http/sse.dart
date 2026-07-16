import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';

import '../json/json.dart';

/// 一条已解析完成的 Server-Sent Event 帧。
///
/// 对应 WHATWG EventSource 规范里一条事件的三个可携带字段;`retry` 字段
/// 按设计文档要求被忽略,不在此值对象中体现。
final class ServerSentEvent with EquatableMixin {
  /// 用给定字段构造一条 SSE 事件;仅 [data] 必填。
  const ServerSentEvent({this.event, required this.data, this.id});

  /// `event:` 字段值;帧中未出现该字段时为 null。
  final String? event;

  /// `data:` 字段值;多行 `data:` 已按换行符合并为单个字符串。
  final String data;

  /// `id:` 字段值;帧中未出现该字段时为 null。
  final String? id;

  @override
  List<Object?> get props => [event, data, id];
}

/// 单条 SSE 帧的可变累积状态(解析过程中的中间态,不对外暴露)。
class _PendingEvent {
  String? event;
  final List<String> dataLines = <String>[];
  String? id;

  bool get hasData => dataLines.isNotEmpty;

  ServerSentEvent? toEventOrNull() {
    if (!hasData) {
      return null;
    }
    return ServerSentEvent(event: event, data: dataLines.join('\n'), id: id);
  }
}

/// 把原始字节流解析为一串 [ServerSentEvent]。
///
/// 语义对齐 WHATWG EventSource 规范的帧语法:
/// - 字节先经 UTF-8 流式解码([utf8.decoder]),正确处理跨块切断的多字节字符;
/// - `\r\n`、`\r`、`\n` 三种换行统一按"行"切分;
/// - `:` 开头的整行视为注释,忽略;
/// - `field: value` 形式中冒号后至多一个前导空格被剥除,其余原样保留;
/// - `data:` 出现多次时按出现顺序以 `\n` 连接;
/// - `retry:` 字段被识别但忽略(不影响 [ServerSentEvent] 的任何字段);
/// - 空行标志一条事件结束,若该事件从未出现过 `data:` 字段则不分发;
/// - 流结束时若存在未被空行终止的残余帧,不分发(数据不完整)。
StreamTransformer<List<int>, ServerSentEvent> sseTransformer() {
  return StreamTransformer<List<int>, ServerSentEvent>(
    (input, cancelOnError) {
      final controller = StreamController<ServerSentEvent>(
        sync: true,
      );
      String buffer = '';
      var pending = _PendingEvent();
      // 上一次 consumeBuffer 处理到缓冲区末尾时，是否恰好以 `\r` 结尾且
      // 尚未判断其后是否紧跟 `\n`（该 `\r` 已经按换行处理并终止了一行，
      // 这里只是记录“如果下一块开头是 `\n`，那是同一个 CRLF 的后半部分，
      // 需要被吞掉，不能再算一次换行”）。
      var pendingCr = false;

      void processLine(String rawLine) {
        if (rawLine.isEmpty) {
          final event = pending.toEventOrNull();
          pending = _PendingEvent();
          if (event != null) {
            controller.add(event);
          }
          return;
        }

        if (rawLine.startsWith(':')) {
          // 注释行，忽略。
          return;
        }

        final colonIndex = rawLine.indexOf(':');
        final String field;
        final String value;
        if (colonIndex == -1) {
          field = rawLine;
          value = '';
        } else {
          field = rawLine.substring(0, colonIndex);
          var rawValue = rawLine.substring(colonIndex + 1);
          if (rawValue.startsWith(' ')) {
            rawValue = rawValue.substring(1);
          }
          value = rawValue;
        }

        switch (field) {
          case 'event':
            pending.event = value;
          case 'data':
            pending.dataLines.add(value);
          case 'id':
            pending.id = value;
          case 'retry':
            // 按设计忽略。
            break;
          default:
            // 未知字段，忽略。
            break;
        }
      }

      void consumeBuffer() {
        // 统一 \r\n / \r / \n 为单一换行边界，逐行处理，
        // 保留缓冲区中尚未被换行终止的残余片段供下次拼接。
        var start = 0;
        final length = buffer.length;
        var i = 0;

        if (pendingCr) {
          // 上一块以孤立 `\r` 结尾（已按换行处理）；若本块开头是 `\n`，
          // 它属于同一个 CRLF，需要吞掉、不再算一次换行。
          pendingCr = false;
          if (length > 0 && buffer[0] == '\n') {
            i = 1;
            start = 1;
          }
        }

        while (i < length) {
          final char = buffer[i];
          if (char == '\n') {
            processLine(buffer.substring(start, i));
            i += 1;
            start = i;
          } else if (char == '\r') {
            processLine(buffer.substring(start, i));
            i += 1;
            if (i < length && buffer[i] == '\n') {
              i += 1;
            } else if (i == length) {
              // `\r` 恰好落在本块末尾，其后是否紧跟 `\n` 要等下一块才知道。
              pendingCr = true;
            }
            start = i;
          } else {
            i += 1;
          }
        }
        buffer = buffer.substring(start);
      }

      final subscription = input.transform(utf8.decoder).listen(
        (chunk) {
          buffer += chunk;
          consumeBuffer();
        },
        onError: controller.addError,
        onDone: controller.close,
        cancelOnError: cancelOnError,
      );

      controller
        ..onPause = subscription.pause
        ..onResume = subscription.resume
        ..onCancel = subscription.cancel;

      return controller.stream.listen(null);
    },
  );
}

/// 把原始字节流解析为一串 JSON 解析结果。
///
/// 管线：[sseTransformer] 完成 SSE 帧解析 → 对每条帧的 `data` 字段调用
/// [safeParseJson]。语义对齐 v7 `parseJsonEventStream`：
/// - `data == '[DONE]'`(如 OpenAI 使用的哨兵)被跳过、不产出任何值，
///   也不主动关闭流——流的结束仍依赖底层字节流自然结束；
/// - 单帧 JSON 解析失败被建模为流内的 [ParseFailure]（可恢复），
///   不中断后续帧的消费；
/// - 连接级错误（底层 [bytes] 本身发生 error）按 [Stream] 语义自然向
///   下游传播，由调用方（更上层的 provider 实现）决定如何处理。
Stream<ParseResult<JsonValue>> parseJsonEventStream(Stream<List<int>> bytes) {
  return bytes.transform(sseTransformer()).expand((event) sync* {
    if (event.data == '[DONE]') {
      return;
    }
    yield safeParseJson(event.data);
  });
}
