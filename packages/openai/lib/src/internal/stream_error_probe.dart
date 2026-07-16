import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

/// 在已解析 SSE 事件流产出首个"输出 chunk"之前循环探测错误帧:命中即
/// throw 契约 [ApiCallError];否则把探测窗口内已读的全部事件与剩余流
/// 无损前拼后返回。
///
/// 语义逐字对齐 v7 `throwIfOpenAIStreamErrorBeforeOutput`(见
/// `raw/openai-stream-error.ts` ~11-63 行)的循环等待"输出 chunk"窗口:
/// - 循环读取 [events] 的每个事件,对每个成功解析的事件依次用
///   [getError] 判定是否为错误帧、用 [isOutputChunk] 判定是否为输出
///   chunk;
/// - [getError] 对某个事件返回非 null 值(错误帧,由调用方按各自 wire
///   的错误形状——chat 的 `{error:{...}}` 信封、responses 的顶层
///   `{type:'error',...}`/带 error 的 `response.failed`——判定并抽取)时,
///   取消迭代器持有的底层订阅(取消传导到上游),再在 [Future] 层同步
///   throw [ApiCallError](经 [_createStreamError]/[_parseStreamError]
///   构造,语义见下)。
/// - [isOutputChunk] 对某个事件返回 true(该事件已是输出内容,如 chat
///   的非空 `delta.content`/`tool_calls`/`annotations`,或 responses 除
///   `response.created`/`response.failed`/`error` 外的其余事件类型)时,
///   停止探测,把探测窗口内已读的全部事件(含这个输出 chunk 本身)与
///   剩余流前拼后返回,交由下游(各 wire 自己的流状态机)继续消费。
/// - 探测窗口内读到的、既非错误帧也非输出 chunk 的元数据帧(如 chat 的
///   空 `delta` 帧、responses 的 `response.created`)按序缓冲,继续读
///   下一个事件——这些帧必须原样前拼保留给下游,下游状态机依赖它们
///   产出 [ResponseMetadata] 等分块。
///
/// pigcode 在此基础上保留两条已定案、且与上游 `stream.tee()` 语义不同的
/// 项目专属处理(round-6 定案,不随本次改动调整):
/// - [events] 为空流(未产出任何事件即结束)时,原样返回一个空流,不
///   throw(对齐 raw `result.done` 分支的 `return streamForConsumer`)。
/// - 探测窗口内([events] 在产出可判定为输出 chunk 的事件前就以 error
///   完成)源流本身的连接级流错误(非 OpenAI 错误帧,如 SSE 连接中途
///   断开)不会从本函数的 [Future] 抛出,而是原样封装进返回的流:下游
///   `listen` 后立即以该错误失败,交由各 wire 自己的流状态机
///   catch→[ErrorPart] 收敛为终态(与「连接级失败 = Stream error 走
///   流内」的项目语义统一,不采用上游 `stream.tee()` 的双读者语义)。
/// - 探测窗口内某个事件解析失败([ParseFailure])时,不视为输出
///   chunk、也不参与 [getError]/[isOutputChunk] 判定(它不具备可供
///   判定的成功解析值),直接停止探测、原样连同已缓冲的帧与剩余流前拼
///   返回,留给下游按"解析失败短路"语义处理。
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
      // probe 窗口内的连接级流错误(如源流未产出任何可解析事件即以 error
      // 完成:EmptyResponseBodyError、连接重置等,也可能发生在已缓冲若干
      // 元数据帧之后)——这类失败不是 OpenAI 错误帧,不适用「Future 抛
      // ApiCallError」语义。项目统一语义是「连接级失败 = Stream error 走
      // 流内」,故不让裸异常从本 Future 抛出,而是先重放已缓冲的帧、再
      // 原样封装该错误进返回的流,交由下游(各 wire 流状态机)的
      // catch→ErrorPart 路径按连接级错误统一处理。
      return _failedStream(buffered, error, stackTrace);
    }

    if (!hasNext) {
      // 流已耗尽:iterator 随流结束自然释放。已缓冲的元数据帧原样返回
      // (对齐 raw `result.done` 分支的 `return streamForConsumer`,只是
      // pigcode 用"已读事件的有限缓冲"取代上游的 `tee()` 双读者)。
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

    // 非错误、非输出的元数据帧(如 chat 空 delta 帧、responses
    // response.created):缓冲后继续读下一个事件。
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
/// 供 probe 窗口内捕获到的连接级流错误使用:已缓冲的元数据帧(若有)
/// 必须无损交还下游,紧随其后下游立即收到该错误,与源流原生以 error
/// 结束时下游看到的行为一致。
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

/// 用错误帧构造 [ApiCallError]。
///
/// 对照 raw `createOpenAIStreamError`:`message` 优先取
/// [_parseStreamError] 解析出的消息,解析失败时兜底为固定文案;
/// `statusCode` 在解析失败时固定为 500,否则走 [_guessStatusCode];
/// `responseBody` 为 [errorFrame] 的 JSON 文本;`data` 为 [errorFrame]
/// 原值。
ApiCallError _createStreamError({
  required JsonValue errorFrame,
  required Uri url,
  required JsonValue requestBody,
}) {
  final streamError = _parseStreamError(errorFrame);
  return ApiCallError(
    message: streamError?.message ??
        'OpenAI stream failed before any output was generated',
    url: url.toString(),
    requestBody: requestBody,
    statusCode: streamError == null ? 500 : _guessStatusCode(streamError),
    responseBody: jsonEncode(errorFrame),
    data: errorFrame,
  );
}

/// 从错误帧中解析出的规范化错误信息(message/code/type)。
final class _StreamError {
  const _StreamError({required this.message, this.code, this.type});

  final String message;
  final Object? code;
  final String? type;
}

/// 解析 [frame] 为 [_StreamError],解析失败(不具备可判定的错误形状)
/// 时返回 null。
///
/// 逐字对照 raw `parseStreamError`(`raw/openai-stream-error.ts` ~90-125
/// 行):
/// - [frame] 非 Map → 返回 null;
/// - `type == 'response.failed'` → 取 `response.error`,其 `message`
///   是 String 才返回 `{message, code, type: 'response.failed'}`,否则
///   返回 null;
/// - 否则:`frame['error']` 是 Map 时取它作为 `error`,否则 `error` 就是
///   `frame` 本身;当 `error['message'] is String` 且(`frame['error']`
///   本身是 Map 或 `error['type'] is String` 或 `error` 含 `code` 键 或
///   `error` 含 `param` 键)时返回 `{message, code, type}`,否则返回
///   null。
_StreamError? _parseStreamError(JsonValue frame) {
  if (frame is! Map<String, Object?>) {
    return null;
  }

  if (frame['type'] == 'response.failed') {
    final response = frame['response'];
    final rawResponseError =
        response is Map<String, Object?> ? response['error'] : null;
    if (rawResponseError is! Map<String, Object?>) {
      return null;
    }
    final message = rawResponseError['message'];
    if (message is! String) {
      return null;
    }
    return _StreamError(
      message: message,
      code: _stringOrNum(rawResponseError['code']),
      type: 'response.failed',
    );
  }

  final envelopeError = frame['error'];
  final isEnvelopeErrorMap = envelopeError is Map<String, Object?>;
  final error = isEnvelopeErrorMap ? envelopeError : frame;
  final message = error['message'];
  if (message is! String) {
    return null;
  }
  final hasDiscriminatingField = isEnvelopeErrorMap ||
      error['type'] is String ||
      error.containsKey('code') ||
      error.containsKey('param');
  if (!hasDiscriminatingField) {
    return null;
  }
  return _StreamError(
    message: message,
    code: _stringOrNum(error['code']),
    type: error['type'] is String ? error['type'] as String : null,
  );
}

Object? _stringOrNum(Object? value) {
  return (value is String || value is num) ? value : null;
}

/// 基于 [error] 的 `code`/`type` 字段猜测 HTTP 状态码。
///
/// 逐字对照 raw `getStatusCode`(`raw/openai-stream-error.ts`)的判定顺序:
/// 1. `code` 是数值且落在 400-599 → 直接用作状态码;
/// 2. `code` 是恰好三位数字的字符串且数值落在 400-599 → 转数值使用;
/// 3. 否则把 `code`(字符串/数值)与 `type`(字符串)拼接、转小写做关键词
///    匹配:`insufficient_quota`/`rate_limit` → 429、`authentication` → 401、
///    `permission` → 403、`not_found` → 404、`invalid`/`bad_request`/
///    `context_length` → 400、`overload` → 503、`timeout` → 504;
/// 4. 都不匹配 → 500(与 raw 默认值一致)。
int _guessStatusCode(_StreamError error) {
  final code = error.code;
  final type = error.type;

  if (code is num && _isHttpErrorStatusCode(code)) {
    return code.toInt();
  }
  if (code is String && RegExp(r'^\d{3}$').hasMatch(code)) {
    final numericCode = int.parse(code);
    if (_isHttpErrorStatusCode(numericCode)) {
      return numericCode;
    }
  }

  final discriminator = <Object?>[code, type]
      .where((value) => value is String || value is num)
      .join(' ')
      .toLowerCase();

  if (discriminator.contains('insufficient_quota') ||
      discriminator.contains('rate_limit')) {
    return 429;
  }
  if (discriminator.contains('authentication')) {
    return 401;
  }
  if (discriminator.contains('permission')) {
    return 403;
  }
  if (discriminator.contains('not_found')) {
    return 404;
  }
  if (discriminator.contains('invalid') ||
      discriminator.contains('bad_request') ||
      discriminator.contains('context_length')) {
    return 400;
  }
  if (discriminator.contains('overload')) {
    return 503;
  }
  if (discriminator.contains('timeout')) {
    return 504;
  }

  return 500;
}

bool _isHttpErrorStatusCode(num value) {
  return value is int && value >= 400 && value <= 599;
}
