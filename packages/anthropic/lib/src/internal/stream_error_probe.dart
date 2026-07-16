import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// 在已解析 SSE 事件流产出首个"输出 chunk"之前循环探测错误帧:命中即
/// throw 契约 [ApiCallError];否则把探测窗口内已读的全部事件与剩余流
/// 无损前拼后返回。
///
/// 适配自 openai 包同名文件的 `throwIfStreamErrorBeforeOutput` 模式;
/// 预读语义对照上游 anthropic 首 chunk 预读(报告 04 §8.1 :2529-2562):
/// Anthropic API 在 overloaded 时也会返回 200 + `error` 事件,故必须在
/// 首个实义事件位置把 `error` 帧升格为 [Future] 层的 [ApiCallError];
/// 非实义帧(如 `ping`)在探测窗口内按序缓冲跳过(:2534-2541)。
///
/// - 循环读取 [events] 的每个事件,对每个成功解析的事件依次用
///   [getError] 判定是否为错误帧、用 [isOutputChunk] 判定是否为输出
///   chunk;
/// - [getError] 返回非 null 值(anthropic wire 为顶层
///   `{type:'error', error:{...}}` 帧的 `error` 对象)时,取消迭代器
///   持有的底层订阅(取消传导到上游),再在 [Future] 层同步 throw
///   [ApiCallError](经 [_createStreamError] 构造,语义见其文档)。
/// - [isOutputChunk] 返回 true(anthropic 除 `ping`/`error` 外的其余
///   事件类型——`message_start` 即产出 part,error 不在首个非 ping 事件
///   位置就属流中段)时,停止探测,把探测窗口内已读的全部事件(含这个
///   输出 chunk 本身)与剩余流前拼后返回,交由下游流状态机继续消费。
/// - 探测窗口内读到的、既非错误帧也非输出 chunk 的帧(`ping`)按序缓冲,
///   继续读下一个事件。
///
/// pigcode 在此基础上保留两条已定案、且与上游 `stream.tee()` 语义不同的
/// 项目专属处理(openai 包 round-6 定案先例,不随本次改动调整):
/// - [events] 为空流(未产出任何事件即结束)时,原样返回一个空流,不
///   throw。
/// - 探测窗口内源流本身的连接级流错误(非 Anthropic 错误帧,如 SSE 连接
///   中途断开)不会从本函数的 [Future] 抛出,而是原样封装进返回的流:
///   下游 `listen` 后立即以该错误失败,交由流状态机 catch→[ErrorPart]
///   收敛为终态(「连接级失败 = Stream error 走流内」的项目语义统一,
///   不采用上游 `stream.tee()` 的双读者语义)。
/// - 探测窗口内某个事件解析失败([ParseFailure])时,不视为输出
///   chunk、也不参与 [getError]/[isOutputChunk] 判定,直接停止探测、
///   原样连同已缓冲的帧与剩余流前拼返回,留给下游按"解析失败短路"
///   语义处理。
Future<Stream<ParseResult<JsonValue>>> throwIfStreamErrorBeforeOutput(
  Stream<ParseResult<JsonValue>> events, {
  required Uri url,
  JsonValue? requestBody,
  required JsonValue? Function(JsonValue value) getError,
  required bool Function(JsonValue value) isOutputChunk,
}) async {
  final iterator = StreamIterator<ParseResult<JsonValue>>(events);
  final buffered = <ParseResult<JsonValue>>[];

  while (true) {
    final bool hasNext;
    try {
      hasNext = await iterator.moveNext();
    } catch (error, stackTrace) {
      // probe 窗口内的连接级流错误:不让裸异常从本 Future 抛出,先重放
      // 已缓冲的帧、再原样封装该错误进返回的流,交由下游流状态机的
      // catch→ErrorPart 路径按连接级错误统一处理。
      return _failedStream(buffered, error, stackTrace);
    }

    if (!hasNext) {
      // 流已耗尽:已缓冲的帧原样返回(空流原样返回,不 throw)。
      return Stream<ParseResult<JsonValue>>.fromIterable(buffered);
    }

    final event = iterator.current;

    if (event is! ParseSuccess<JsonValue>) {
      // 解析失败帧:停止探测,原样连同已缓冲的帧与剩余流前拼返回。
      buffered.add(event);
      return _prependAll(buffered, iterator);
    }

    final errorFrame = getError(event.value);
    if (errorFrame != null) {
      // 取消迭代器持有的底层订阅,把取消传导到上游(如 HTTP 响应流),
      // 再在 Future 层同步抛出——不把错误帧塞进返回的流里。
      await iterator.cancel();
      throw _createStreamError(
        errorFrame: errorFrame,
        url: url,
        requestBody: requestBody,
      );
    }

    if (isOutputChunk(event.value)) {
      // 已是输出 chunk:停止探测,连同已缓冲的帧与剩余流(含本事件)
      // 前拼返回。
      buffered.add(event);
      return _prependAll(buffered, iterator);
    }

    // 非错误、非输出的帧(ping):缓冲后继续读下一个事件。
    buffered.add(event);
  }
}

/// 把已读的 [buffered] 事件序列与 [iterator] 剩余部分拼接为单订阅流。
///
/// 只允许单次订阅(不重复消费 [iterator]);下游取消时把取消传导给
/// [iterator](进而传导到其底层订阅的上游)。
Stream<ParseResult<JsonValue>> _prependAll(
  List<ParseResult<JsonValue>> buffered,
  StreamIterator<ParseResult<JsonValue>> iterator,
) {
  late StreamController<ParseResult<JsonValue>> controller;
  controller = StreamController<ParseResult<JsonValue>>(
    onListen: () async {
      buffered.forEach(controller.add);
      try {
        while (await iterator.moveNext()) {
          controller.add(iterator.current);
        }
        await controller.close();
      } catch (error, stackTrace) {
        controller.addError(error, stackTrace);
        await controller.close();
      }
    },
    onCancel: () async {
      await iterator.cancel();
    },
  );
  return controller.stream;
}

/// 构造一个订阅即先重放 [buffered]、再以 [error] 失败(随后 close)的流。
///
/// 供 probe 窗口内捕获到的连接级流错误使用:已缓冲的帧(若有)必须无损
/// 交还下游,紧随其后下游立即收到该错误,与源流原生以 error 结束时下游
/// 看到的行为一致。
Stream<ParseResult<JsonValue>> _failedStream(
  List<ParseResult<JsonValue>> buffered,
  Object error,
  StackTrace stackTrace,
) {
  late StreamController<ParseResult<JsonValue>> controller;
  controller = StreamController<ParseResult<JsonValue>>(
    onListen: () {
      buffered.forEach(controller.add);
      controller.addError(error, stackTrace);
      unawaited(controller.close());
    },
  );
  return controller.stream;
}

/// 用 anthropic `error` 事件的 `error` 对象构造 [ApiCallError]。
///
/// 逐字对照上游首 chunk 预读的抛错语义(报告 04 §8.1 :2543-2557):
/// `message: error.message`、`statusCode: overloaded ? 529 : 500`、
/// `isRetryable: error.type === 'overloaded_error'`(**显式传递**,非
/// overloaded 的 500 需要显式 false,不依赖 5xx 默认推断)、
/// `responseBody: JSON.stringify(error)`、`data` 为 [errorFrame] 原值,
/// url/requestBody 透传。
ApiCallError _createStreamError({
  required JsonValue errorFrame,
  required Uri url,
  required JsonValue requestBody,
}) {
  final error =
      errorFrame is JsonObject ? errorFrame : const <String, Object?>{};
  final isOverloaded = error['type'] == 'overloaded_error';
  final message = error['message'];
  return ApiCallError(
    message: message is String
        ? message
        : 'Anthropic stream failed before any output was generated',
    url: url.toString(),
    requestBody: requestBody,
    statusCode: isOverloaded ? 529 : 500,
    isRetryable: isOverloaded,
    responseBody: jsonEncode(errorFrame),
    data: errorFrame,
  );
}
