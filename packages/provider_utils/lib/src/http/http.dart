import 'dart:async';
import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:http/http.dart' as http;

import '../json/json.dart';

/// 从左到右合并多个 header map。
///
/// - `headerMaps` 中的 `null` 元素直接跳过。
/// - 每个 map 内部值为 `null` 的条目会被剔除(不会出现在结果中)。
/// - header 名称按 HTTP 语义大小写不敏感;后面的 map 中同名 key 覆盖前面的
///   值,覆盖期间保留被覆盖 key 的 casing。
/// - 若后面的 map 把某个 key 的值设为 `null`,该 key 会被移除,即使更早的
///   map 里有非 null 值。
Map<String, String> combineHeaders(
  List<Map<String, String?>?> headerMaps,
) {
  final combined = <String, String>{};
  final actualNames = <String, String>{};
  for (final headers in headerMaps) {
    if (headers == null) {
      continue;
    }
    for (final entry in headers.entries) {
      final normalizedName = entry.key.toLowerCase();
      final actualName = actualNames[normalizedName];
      final value = entry.value;
      if (value == null) {
        if (actualName != null) {
          combined.remove(actualName);
          actualNames.remove(normalizedName);
        }
      } else if (actualName != null) {
        combined[actualName] = value;
      } else {
        combined[entry.key] = value;
        actualNames[normalizedName] = entry.key;
      }
    }
  }
  return combined;
}

/// 一次 HTTP 请求/响应的上下文,传给响应处理策略(见 `response_handler.dart`)。
final class ResponseContext {
  const ResponseContext({
    required this.url,
    this.requestBody,
    required this.response,
  });

  /// 请求的目标 URL。
  final Uri url;

  /// 请求体的逻辑值(诊断用,非物理编码后的字符串)。
  final JsonValue? requestBody;

  /// 底层 HTTP 流式响应。
  final http.StreamedResponse response;
}

/// 处理一次成功响应,产出业务值 `T`。
typedef ResponseHandler<T> = Future<T> Function(ResponseContext ctx);

/// 处理一次失败响应(非 2xx),产出待抛出的 [ApiCallError]。
typedef FailedResponseHandler = Future<ApiCallError> Function(
  ResponseContext ctx,
);

/// 把传输层异常(连接失败、超时等,尚未拿到 HTTP 响应)归一化为
/// [ApiCallError]。
///
/// 语义上,没有响应意味着无法据状态码判断是否可重试,因此显式
/// `isRetryable: true`(网络错误的默认策略是允许重试);`statusCode` 恒为
/// `null`。原始异常保留在 [ApiCallError.cause] 中以便诊断。
ApiCallError mapTransportError(
  Object error, {
  required Uri url,
  JsonValue? requestBody,
}) {
  return ApiCallError(
    message: 'Cannot connect to API: $error',
    url: url.toString(),
    requestBody: requestBody,
    statusCode: null,
    isRetryable: true,
    cause: error,
  );
}

/// [postJsonToApi] 与 [postJsonStreamToApi] 共用的发送与状态码分派逻辑。
///
/// 构造请求、发送、识别取消/传输层异常、按 2xx/非 2xx 分派到
/// `successHandler`/`failureHandler`,均在此完成;两个公开函数的差异
/// 只在于 owned client 的关闭时机,由各自的调用处处理。
Future<T> _sendAndDispatch<T>({
  required Uri url,
  Map<String, String>? headers,
  required JsonValue body,
  required ResponseHandler<T> successHandler,
  required FailedResponseHandler failureHandler,
  required http.Client httpClient,
  CancellationSignal? cancellation,
}) async {
  // 用小写 'content-type' 与 package:http 的规范化形态一致。说明:http 的
  // BaseRequest.headers 本就是大小写不敏感 map(已实测:大写键同样被 body
  // setter 识别、不会误加 text/plain),此处小写仅为卫生一致性,非行为修复。
  final combinedHeaders = combineHeaders([
    {'content-type': 'application/json'},
    headers,
  ]);

  final request = http.AbortableRequest(
    'POST',
    url,
    abortTrigger: cancellation?.whenCancelled,
  )
    ..headers.addAll(combinedHeaders)
    ..body = jsonEncode(body);

  final http.StreamedResponse response;
  try {
    response = await httpClient.send(request);
  } catch (error) {
    if (error is http.RequestAbortedException) {
      rethrow;
    }
    throw mapTransportError(error, url: url, requestBody: body);
  }

  final ctx = ResponseContext(
    url: url,
    requestBody: body,
    response: response,
  );

  final statusCode = response.statusCode;
  if (statusCode >= 200 && statusCode < 300) {
    return await successHandler(ctx);
  }

  throw await failureHandler(ctx);
}

/// 以 JSON 编码的请求体发起一次 POST 请求。
///
/// 行为:
/// - `headers` 与固定的 `Content-Type: application/json` 通过
///   [combineHeaders] 合并(后者覆盖前者的同名 key,因此调用方可覆盖
///   默认 Content-Type)。
/// - `body` 用 `jsonEncode` 编码后作为物理请求体发送;[ResponseContext]
///   中回填的是编码前的逻辑值 `body`,供错误上下文/日志使用。
/// - `client` 可注入(测试/复用连接池);缺省时内部临时创建一个
///   `http.Client()`,并在结束时妥善 `close()`;注入的 client 生命周期
///   由调用方管理,本函数不会关闭它。
/// - `cancellation` 提供时,其 `whenCancelled` 作为
///   `http.AbortableRequest.abortTrigger`,取消会使底层 `Client.send`
///   以 [http.RequestAbortedException] 结束;该异常(及其他非
///   `ApiCallError` 的 `http.ClientException`/其他传输层异常里,专属于
///   取消的这一支)按类型识别后原样 `rethrow`,不包装为 [ApiCallError]。
/// - 2xx 状态码交给 `successHandler` 处理并返回其结果;非 2xx 状态码交给
///   `failureHandler` 产出 [ApiCallError] 并抛出。
/// - 发送阶段(`client.send`)抛出的传输层异常(如 `http.ClientException`、
///   `TimeoutException`)经 [mapTransportError] 归一化后抛出。
///
/// **注意**:若 `successHandler` 产出一个仍需异步消费的 `Stream`(如
/// [eventSourceResponseHandler]),不要用本函数——本函数在 `successHandler`
/// 返回后立即进入 `finally` 关闭 owned client,会拆断尚未被下游消费完的
/// 流式连接。这类场景请改用 [postJsonStreamToApi],它会把 owned client
/// 的关闭推迟到流真正结束(完成/出错/被取消)之后。
Future<T> postJsonToApi<T>({
  required Uri url,
  Map<String, String>? headers,
  required JsonValue body,
  required ResponseHandler<T> successHandler,
  required FailedResponseHandler failureHandler,
  http.Client? client,
  CancellationSignal? cancellation,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();

  try {
    return await _sendAndDispatch<T>(
      url: url,
      headers: headers,
      body: body,
      successHandler: successHandler,
      failureHandler: failureHandler,
      httpClient: httpClient,
      cancellation: cancellation,
    );
  } finally {
    if (ownedClient) {
      httpClient.close();
    }
  }
}

/// 以 JSON 编码的请求体发起一次 POST 请求,`successHandler` 产出一个待
/// 异步消费的事件流(典型如 [eventSourceResponseHandler])。
///
/// 与 [postJsonToApi] 的请求发送、取消桥接、传输层异常归一化、2xx/非 2xx
/// 分派语义完全一致(共用私有辅助完成,不重复实现);唯一差异是 owned
/// client(未注入 `client` 时内部创建的临时 `http.Client`)的关闭时机:
/// - 非 2xx / 传输层异常 / `successHandler` 同步抛出的校验错误等失败路径:
///   owned client 在异常向上抛出前关闭,不泄漏连接。
/// - 2xx 且 `successHandler` 正常返回流:owned client **不会**随本函数的
///   `Future` 完成而关闭,而是把返回的流包一层——在其 `onDone`/`onError`/
///   `onCancel` 三条路径中的任意一条先触发时关闭 owned client;三条路径
///   互斥(用幂等标志保护),避免重复调用 `http.Client.close()`（其重复
///   调用行为未获 `package:http` 约定保证）。
/// - 注入的 `client` 一律不由本函数关闭,生命周期由调用方管理,与
///   [postJsonToApi] 约定一致。
Future<Stream<ParseResult<T>>> postJsonStreamToApi<T>({
  required Uri url,
  Map<String, String>? headers,
  required JsonValue body,
  required ResponseHandler<Stream<ParseResult<T>>> successHandler,
  required FailedResponseHandler failureHandler,
  http.Client? client,
  CancellationSignal? cancellation,
}) async {
  final ownedClient = client == null;
  final httpClient = client ?? http.Client();

  final Stream<ParseResult<T>> upstream;
  try {
    upstream = await _sendAndDispatch<Stream<ParseResult<T>>>(
      url: url,
      headers: headers,
      body: body,
      successHandler: successHandler,
      failureHandler: failureHandler,
      httpClient: httpClient,
      cancellation: cancellation,
    );
  } catch (_) {
    // 失败路径(非 2xx / 传输层异常 / successHandler 抛出的校验错误等):
    // 没有流需要保活,owned client 在异常抛出前关闭。
    if (ownedClient) {
      httpClient.close();
    }
    rethrow;
  }

  if (!ownedClient) {
    // 注入的 client 生命周期由调用方管理,原样转发即可。
    return upstream;
  }

  late final StreamSubscription<ParseResult<T>> subscription;
  final controller = StreamController<ParseResult<T>>();

  // done/error/cancel 三条路径都可能触发 owned client 的关闭，但彼此
  // 互斥执行的先后顺序不固定（如 error 后调用方仍可能 cancel 订阅）；
  // 用该标志保证 `httpClient.close()` 只被调用一次——`http.Client.close()`
  // 重复调用的行为未获 `package:http` 约定保证，防御为妥。
  var ownedClientClosed = false;
  void closeOwnedClientOnce() {
    if (!ownedClientClosed) {
      ownedClientClosed = true;
      httpClient.close();
    }
  }

  subscription = upstream.listen(
    controller.add,
    onError: (Object error, StackTrace stackTrace) {
      closeOwnedClientOnce();
      controller.addError(error, stackTrace);
    },
    onDone: () {
      closeOwnedClientOnce();
      controller.close();
    },
  );

  controller
    ..onPause = subscription.pause
    ..onResume = subscription.resume
    ..onCancel = () async {
      await subscription.cancel();
      closeOwnedClientOnce();
    };

  return controller.stream;
}
