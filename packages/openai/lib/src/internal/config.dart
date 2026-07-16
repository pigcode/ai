import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

import 'web_socket_channel_connector.dart';

/// Creates a WebSocket connection for OpenAI realtime endpoints.
typedef OpenAiWebSocketConnector = OpenAiWebSocketConnection Function(
  Uri url, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
});

/// Minimal WebSocket surface used by OpenAI realtime APIs.
abstract interface class OpenAiWebSocketConnection {
  /// Completes once the connection is ready for client messages.
  Future<void> get ready;

  /// Messages received from the remote endpoint.
  Stream<Object?> get stream;

  /// Sends a client message.
  void add(Object? data);

  /// Closes the connection.
  Future<void> close([int? closeCode, String? closeReason]);
}

/// Default cross-platform WebSocket connector.
OpenAiWebSocketConnection connectOpenAiWebSocket(
  Uri url, {
  Iterable<String>? protocols,
  Map<String, String>? headers,
}) =>
    _OpenAiWebSocketChannelConnection(
      connectWebSocketChannel(
        url,
        protocols: effectiveWebSocketProtocols(
          protocols,
          headers: headers,
        ),
        headers: headers,
      ),
    );

final class _OpenAiWebSocketChannelConnection
    implements OpenAiWebSocketConnection {
  _OpenAiWebSocketChannelConnection(this._channel);

  final WebSocketChannel _channel;

  @override
  Future<void> get ready => _channel.ready;

  @override
  Stream<Object?> get stream => _channel.stream;

  @override
  void add(Object? data) {
    _channel.sink.add(data);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) =>
      _channel.sink.close(closeCode, closeReason);
}

/// OpenAI chat 与 responses 两套 wire 共用的运行时配置。
///
/// 由 `lib/src/openai_provider.dart` 的 `createOpenAi` 工厂构造,经
/// `OpenAiChatLanguageModel`/`OpenAiResponsesLanguageModel` 消费,承载
/// 请求两套 wire 都需要的公共信息(provider 标识、baseURL、每请求求值的
/// headers、可选注入的 HTTP client),自身不含任何业务逻辑。
final class OpenAiConfig {
  /// 用给定字段构造一份配置。
  const OpenAiConfig({
    required this.providerName,
    required this.baseUrl,
    required this.headers,
    this.client,
    this.webSocketConnector = connectOpenAiWebSocket,
  });

  /// provider 标识(如 `'openai'`),用作 `LanguageModel.provider` 的前缀。
  final String providerName;

  /// API 基地址,已由调用方(`createOpenAi`)去除尾部斜杠。
  final String baseUrl;

  /// 每次请求求值一次的 header 构造函数,承载 `Authorization`/自定义
  /// UA 等——不在配置构造时求值缓存,允许调用方在 headers 回调内动态
  /// 变化(如轮换 key)。
  final Map<String, String> Function() headers;

  /// 可选注入的 `http.Client`;为 `null` 时由 `pigcode_ai_provider_utils` 的
  /// `postJsonToApi`/`postJsonStreamToApi` 各自临时创建并妥善关闭。
  final http.Client? client;

  /// WebSocket 连接器;默认使用跨平台 `web_socket_channel`。
  final OpenAiWebSocketConnector webSocketConnector;
}
