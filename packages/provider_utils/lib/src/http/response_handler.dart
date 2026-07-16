import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;

import 'http.dart';
import '../json/json.dart';
import 'sse.dart';

/// 成功响应(2xx)的 JSON 解码 handler。
///
/// 读取 [ResponseContext.response] 的完整流式 body 并按 UTF-8 解码为文本;
/// body 去除首尾空白后为空字符串时,视为契约层 `EmptyResponseBodyError`
/// 场景直接抛出。非空文本先经 [safeParseJson] 语法解析——解析失败时
/// 直接原样抛出其携带的 `JsonParseError`,不重复包装。语法解析成功后,
/// 若提供 [validator] 则对解析结果做结构校验;校验失败同样原样抛出
/// `TypeValidationError`。最终把（可能经校验规整过的）值交给 [decode]
/// 转换为业务类型 [T]。
ResponseHandler<T> jsonResponseHandler<T>({
  JsonSchemaValidator? validator,
  required T Function(JsonValue json) decode,
}) {
  return (ResponseContext ctx) async {
    final bytes = await ctx.response.stream.toBytes();
    final text = utf8.decode(bytes);

    if (text.trim().isEmpty) {
      throw const EmptyResponseBodyError();
    }

    final parseResult = safeParseJson(text);
    if (parseResult is ParseFailure<JsonValue>) {
      throw parseResult.error;
    }

    final parsed = (parseResult as ParseSuccess<JsonValue>).value;

    JsonValue value = parsed;
    if (validator != null) {
      final validationResult = validator.validate(parsed);
      if (validationResult is ValidationFailure) {
        throw validationResult.error;
      }
      value = (validationResult as ValidationSuccess).value;
    }

    return decode(value);
  };
}

/// 失败响应(非 2xx)的 JSON 错误体解码 handler,三层降级保证不掩盖原始
/// HTTP 错误:
///
/// 1. body 去除首尾空白后为空 —— 用 [http.StreamedResponse.reasonPhrase]
///    兜底作为 message(reasonPhrase 为 null/空时再兜底 `'HTTP <statusCode>'`,
///    错误消息永不为空串),不带结构化 `data`。
/// 2. body 非空但语法解析失败、提供了 [validator] 且结构校验失败,或
///    [errorToMessage] 提取消息时抛出(错误体形状不符预期)—— 同样退回
///    上述兜底,不带 `data`。
/// 3. 解析、校验与消息提取都成功 —— 用 [errorToMessage] 生成的人类可读
///    message,并把解析值整体存入 `data`。
///
/// 三层最终都返回构造好的 `ApiCallError`(不是抛出),交给调用方决定何时
/// 真正抛出——与契约的"错误作为可携带数据的值"一致。
///
/// [isRetryable] 若提供,针对每一层显式回调覆盖契约默认的按状态码推断;
/// 未提供时不传该具名参数,`ApiCallError.isRetryable` getter 自动按状态码
/// 推断。
FailedResponseHandler jsonErrorResponseHandler({
  JsonSchemaValidator? validator,
  required String Function(JsonValue json) errorToMessage,
  bool Function(http.StreamedResponse response, JsonValue? parsedError)?
      isRetryable,
}) {
  return (ResponseContext ctx) async {
    final response = ctx.response;
    // 错误体的读取本身可能失败(如对端发出 500/429 状态头后中途重置连接):
    // 此时 body 不可得,但 status/headers/url/可重试性已知——按空 body 走
    // 下面的降级链,不让读取异常旁路错误映射。
    // 读取成功时,错误体可能来自二进制或传统编码的代理错误页(不保证是
    // 合法 UTF-8):用 allowMalformed 把非法字节替换为 U+FFFD 而非严格解码
    // 抛出 FormatException——否则同样会绕过降级、丢失原始 HTTP 失败上下文。
    String text;
    try {
      final bytes = await response.stream.toBytes();
      text = utf8.decode(bytes, allowMalformed: true);
    } on http.RequestAbortedException {
      // 取消不包装:headers 到达后触发取消时,RequestAbortedException 出现在
      // body 流的消费过程中(package:http 文档约定)——必须原样透传,不得
      // 转成(甚至按状态码被推断为可重试的)ApiCallError 而丢失取消信号。
      rethrow;
    } catch (_) {
      text = '';
    }

    ApiCallError fallback() {
      // reasonPhrase 可为 null 或空(如 HTTP/2 无 reason phrase);再兜底到
      // 'HTTP <statusCode>',保证错误消息永不为空串。
      final phrase = response.reasonPhrase;
      return ApiCallError(
        message: (phrase == null || phrase.isEmpty)
            ? 'HTTP ${response.statusCode}'
            : phrase,
        url: ctx.url.toString(),
        requestBody: ctx.requestBody,
        statusCode: response.statusCode,
        responseHeaders: response.headers,
        responseBody: text,
        isRetryable: isRetryable?.call(response, null),
      );
    }

    if (text.trim().isEmpty) {
      return fallback();
    }

    final parseResult = safeParseJson(text);
    if (parseResult is ParseFailure<JsonValue>) {
      return fallback();
    }

    JsonValue parsed = (parseResult as ParseSuccess<JsonValue>).value;
    if (validator != null) {
      final validationResult = validator.validate(parsed);
      if (validationResult is ValidationFailure) {
        return fallback();
      }
      parsed = (validationResult as ValidationSuccess).value;
    }

    // 错误体是合法 JSON 但形状不符 [errorToMessage] 预期(如代理/网关返回
    // 不同的错误信封、或 validator 过宽)时,提取本身可能抛 cast/null 异常
    // ——与其他畸形错误体同等对待,退回 fallback,保留原始 HTTP 失败上下文
    // (status/headers/body/可重试性),不让裸异常旁路错误映射。
    final String message;
    try {
      message = errorToMessage(parsed);
    } catch (_) {
      return fallback();
    }

    return ApiCallError(
      message: message,
      url: ctx.url.toString(),
      requestBody: ctx.requestBody,
      statusCode: response.statusCode,
      responseHeaders: response.headers,
      responseBody: text,
      data: parsed,
      isRetryable: isRetryable?.call(response, parsed),
    );
  };
}

/// 成功响应(2xx)的 SSE 事件流 handler。
///
/// handler 本身不等待任何字节:拿到 [ResponseContext] 后立即返回一个已
/// 包装好的流,不会阻塞在“首字节是否到达”上。v7 用同步的
/// `response.body == null` 表达空 body 语义,但 Dart
/// `http.StreamedResponse.stream` 恒非 `null`、也没有等价的同步属性可
/// 供判断;因此空 body 语义改为在**返回的流内部**表达:若源流在产出
/// 任何字节前就已正常结束,视为空 body,向返回的流 `addError` 契约
/// `EmptyResponseBodyError` 后关闭(空 body 归类为连接级错误,与
/// “连接级失败 = Stream error、由 provider 层 `doStream` 捕获转换为
/// 契约 `ErrorPart`”的既定语义一致)。
///
/// 把包装后的字节流交给 [parseJsonEventStream] 做 SSE 帧解析,再对每个
/// `ParseResult<JsonValue>` 施加 [decode]:
/// - 已解析成功的帧,用 [decode] 转换出业务类型 [T];[decode] 本身抛错
///   视为该帧不符合期望结构,转换为携带 `TypeValidationError`(或原样
///   透传已是 `AiError` 的异常)的 `ParseFailure<T>`,不中断流。
/// - 帧级解析失败(语法错误)的 [ParseFailure] 原样转换类型参数继续
///   转发,同样不中断流。
///
/// 源流本身的连接级失败(非空 body 场景)不在此处捕获,作为 `Stream`
/// error 原样传播给下游——由 provider 层的 `doStream` 捕获转换为契约
/// `ErrorPart`,职责边界见设计文档 §3.4。
ResponseHandler<Stream<ParseResult<T>>> eventSourceResponseHandler<T>({
  required T Function(JsonValue json) decode,
}) {
  return (ResponseContext ctx) async {
    final controller = StreamController<List<int>>();
    var sawBytes = false;
    // 源流是否已经转发过 error:「先 error 后 close」是 Stream.error(...)/
    // addError+close 的标准形态,此时 onDone 不得再补发 EmptyResponseBodyError
    // ——否则一个连接错误会变成两个终端失败,且第二个被误分类为空 body。
    var sawError = false;

    // onData/onError/onDone 必须作为 `listen(...)` 的参数一次性装好，不能
    // 先 `listen(null)` 再事后用级联赋值补上——若源流在订阅建立期间
    // （`onListen` 回调内）就同步派发块甚至随即结束，事后赋值之前出现的
    // 空档会让这些同步事件被空 handler 吞掉，导致首块丢失或误报空 body。
    final subscription = ctx.response.stream.listen(
      (chunk) {
        // 只有非空块才算「见过字节」:空 List<int> 块(部分 client/代理会发)
        // 不代表 body 有内容,不得抑制空 body 判定。块本身照常转发。
        if (chunk.isNotEmpty) {
          sawBytes = true;
        }
        controller.add(chunk);
      },
      onError: (Object error, StackTrace stackTrace) {
        // 连接级失败:原样转发为返回流的 error，不在此处包装。
        sawError = true;
        controller.addError(error, stackTrace);
      },
      onDone: () {
        // 仅「全程无字节且无错误」才算空 body;已转发过连接错误时不再补发。
        if (!sawBytes && !sawError) {
          controller.addError(const EmptyResponseBodyError());
        }
        controller.close();
      },
    );

    controller
      ..onPause = subscription.pause
      ..onResume = subscription.resume
      ..onCancel = () async {
        await subscription.cancel();
      };

    return parseJsonEventStream(controller.stream).map((event) {
      if (event is ParseFailure<JsonValue>) {
        return ParseFailure<T>(event.error, rawValue: event.rawValue);
      }
      final success = event as ParseSuccess<JsonValue>;
      try {
        final decoded = decode(success.value);
        return ParseSuccess<T>(decoded, rawValue: success.rawValue);
      } on AiError catch (error) {
        return ParseFailure<T>(error, rawValue: success.rawValue);
      } catch (error) {
        return ParseFailure<T>(
          TypeValidationError(value: success.value, cause: error),
          rawValue: success.rawValue,
        );
      }
    });
  };
}
