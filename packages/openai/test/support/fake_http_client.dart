import 'dart:async';

import 'package:http/http.dart' as http;

/// 离线测试用的可编程 `http.Client`。
///
/// 三种互斥的行为模式,按构造参数选择其一:
/// - `responseBuilder` 非空:对每次 `send` 调用产出可编程的
///   [http.StreamedResponse]。
/// - `exceptionToThrow` 非空:`send` 立即抛出给定异常(用于模拟传输层失败)。
/// - `awaitAbort` 为 `true`:`send` 等待请求的 `abortTrigger` 完成后,
///   记录 [abortObserved] 并抛出 [http.RequestAbortedException](模拟
///   `package:http` 真实客户端对取消请求的处理)。
///
/// 同时记录每次 `send` 收到的请求,供测试断言 headers/body。
final class FakeHttpClient extends http.BaseClient {
  FakeHttpClient({
    this.responseBuilder,
    this.exceptionToThrow,
    this.awaitAbort = false,
  });

  /// 产出响应的回调(成功/失败路径测试用)。
  final Future<http.StreamedResponse> Function(http.BaseRequest request)?
      responseBuilder;

  /// `send` 应立即抛出的异常(传输层错误测试用)。
  final Object? exceptionToThrow;

  /// 是否等待请求的 `abortTrigger` 完成后再以
  /// [http.RequestAbortedException] 结束(取消测试用)。
  final bool awaitAbort;

  /// 已发送的请求,按发送顺序记录。
  final List<http.BaseRequest> recordedRequests = <http.BaseRequest>[];

  /// 已发送请求的 body 文本,与 [recordedRequests] 按下标一一对应
  /// (仅对 `http.Request` 有效;其余请求类型不记录)。
  final List<String> recordedBodies = <String>[];

  /// `close()` 是否被调用过。
  bool closed = false;

  /// [awaitAbort] 模式下,`abortTrigger` 是否已被观察到触发。
  bool abortObserved = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    recordedRequests.add(request);
    if (request is http.Request) {
      recordedBodies.add(request.body);
    }

    if (awaitAbort) {
      final abortTrigger = (request as http.Abortable).abortTrigger;
      if (abortTrigger == null) {
        throw StateError(
          'FakeHttpClient.awaitAbort requires the request to carry an '
          'abortTrigger.',
        );
      }
      await abortTrigger;
      abortObserved = true;
      throw http.RequestAbortedException(request.url);
    }

    if (exceptionToThrow != null) {
      throw exceptionToThrow!;
    }

    final builder = responseBuilder;
    if (builder == null) {
      throw StateError(
        'FakeHttpClient requires responseBuilder, exceptionToThrow, or '
        'awaitAbort to be configured.',
      );
    }
    return builder(request);
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

/// 构造一个即时完成的 [http.StreamedResponse],用于成功/失败路径测试。
http.StreamedResponse fakeStreamedResponse({
  required int statusCode,
  String body = '',
  Map<String, String> headers = const {},
  String reasonPhrase = '',
}) {
  return http.StreamedResponse(
    Stream.value(body.codeUnits),
    statusCode,
    headers: headers,
    reasonPhrase: reasonPhrase,
  );
}

/// 可观察上游订阅是否被取消的字节流源。
///
/// 用于验证"下游取消 → 上游连接被取消"的传导语义。构造时给定的
/// `chunks` 依次发出后,流**不会自然结束**——模拟真实的长连接
/// (SSE/chunked 响应在收到更多数据前不会主动关闭),因此后续是否停止
/// 完全取决于取消是否被正确传导。[wasCancelled] 在该流的
/// `StreamController.onCancel` 触发后翻转为 `true`。
class ObservableByteStream {
  ObservableByteStream(List<List<int>> chunks) {
    late final StreamController<List<int>> controller;
    controller = StreamController<List<int>>(
      onListen: () async {
        for (final chunk in chunks) {
          controller.add(chunk);
          // 让每个 chunk 的分发跨越一次事件循环,便于测试在帧之间插入
          // "消费到一半就取消" 的时机。发完给定 chunk 后刻意不关闭
          // controller,模拟迟迟不结束的长连接。
          await Future<void>.delayed(Duration.zero);
        }
      },
      onCancel: () {
        wasCancelled = true;
      },
    );
    stream = controller.stream;
  }

  /// 供 [http.StreamedResponse] 使用的字节流。
  late final Stream<List<int>> stream;

  /// 该流的订阅是否已被取消(下游取消传导到此处的观察点)。
  bool wasCancelled = false;
}
