import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_mcp/pigcode_ai_mcp.dart';
import 'package:pigcode_ai_mcp/pigcode_ai_mcp_http.dart';
import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

const _cimdClientId = 'https://conformance-test.local/client-metadata.json';
final _redirectUri = Uri.parse('http://127.0.0.1:49152/oauth/callback');

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln('Usage: mcp_conformance_client.dart <server-url>');
    exitCode = 64;
    return;
  }
  final endpoint = Uri.parse(arguments.single);
  final scenario = Platform.environment['MCP_CONFORMANCE_SCENARIO'] ?? '';
  final packageClient = http.Client();
  try {
    if (scenario == 'sse-retry') {
      await _runSseRetry(endpoint, packageClient);
    } else if (scenario.startsWith('auth/')) {
      await _runAuthorization(endpoint, scenario, packageClient);
    } else {
      await _runCore(endpoint, scenario, packageClient);
    }
  } finally {
    packageClient.close();
  }
}

Future<void> _runCore(
  Uri endpoint,
  String scenario,
  http.Client packageClient,
) async {
  final elicitation = scenario == 'elicitation-sep1034-client-defaults';
  final runtime = _createClient(
    endpoint,
    packageClient,
    elicitation: elicitation,
  );
  try {
    await runtime.client.initialize();
    if (elicitation) {
      await runtime.transport.openServerStream();
    }
    switch (scenario) {
      case 'initialize':
        break;
      case 'tools_call':
        await _callFirstTool(
          runtime.client,
          const <String, Object?>{'a': 2, 'b': 3},
        );
      case 'elicitation-sep1034-client-defaults':
        await _callFirstTool(runtime.client, const <String, Object?>{});
      default:
        throw UnsupportedError(
          'Client conformance scenario is not implemented: $scenario',
        );
    }
  } finally {
    await runtime.client.close();
  }
}

Future<void> _runSseRetry(
  Uri endpoint,
  http.Client packageClient,
) async {
  final transport = McpHttpClientTransport(
    httpClient: McpPackageHttpClient(packageClient),
    endpoint: endpoint,
  );
  final peer = JsonRpcPeer(transport: transport);
  try {
    await peer.request(
      'initialize',
      params: const <String, Object?>{
        'protocolVersion': '2025-11-25',
        'capabilities': <String, Object?>{},
        'clientInfo': <String, Object?>{
          'name': 'pigcode-ai-mcp-conformance-client',
          'version': '0.0.1',
        },
      },
    );
    await peer.notify(
      'notifications/initialized',
      params: const <String, Object?>{},
    );
    await peer.request(
      'tools/list',
      params: const <String, Object?>{},
    );
    await peer.request(
      'tools/call',
      params: const <String, Object?>{
        'name': 'test_reconnection',
        'arguments': <String, Object?>{},
      },
      timeout: const Duration(seconds: 5),
    );
  } finally {
    await peer.close();
  }
}

Future<void> _runAuthorization(
  Uri endpoint,
  String scenario,
  http.Client packageClient,
) async {
  final store = _MemoryAuthorizationStore();
  final browser = _AutomatedBrowser(packageClient);
  final context = _conformanceContext();
  final coordinator = McpAuthorizationCoordinator(
    resource: endpoint,
    httpClient: _PackageAuthorizationHttpClient(packageClient),
    store: store,
    browser: browser,
    redirectReceiver: browser,
    registrationProvider: _ConformanceRegistrationProvider(
      scenario: scenario,
      context: context,
    ),
    random: _RandomSource(),
    maxScopeRetries: 2,
  );
  var runtime = _createClient(
    endpoint,
    packageClient,
    authorizationProvider: coordinator,
  );
  try {
    try {
      await runtime.client.initialize();
    } on McpHttpStatusException catch (challenge) {
      await coordinator.authorize(
        redirectUri: _redirectUri,
        wwwAuthenticate: challenge.header('www-authenticate'),
      );
      await runtime.client.close();
      runtime = _createClient(
        endpoint,
        packageClient,
        authorizationProvider: coordinator,
      );
      await runtime.client.initialize();
    }

    if (scenario == 'auth/scope-retry-limit') {
      await _runScopeRetry(runtime.client, coordinator);
      return;
    }

    McpListToolsResult tools;
    try {
      tools = await runtime.client.listTools(mcpPageRequest());
    } on McpHttpStatusException catch (challenge) {
      await _authorizeForChallenge(
        coordinator,
        challenge,
        hasToken: await store.load(endpoint) != null,
      );
      tools = await runtime.client.listTools(mcpPageRequest());
    }

    final definition =
        ((tools.toJson()! as Map<String, Object?>)['tools']! as List<Object?>)
            .cast<Map<String, Object?>>()
            .first;
    final name = definition['name']! as String;
    try {
      await runtime.client.callTool(
        McpCallToolRequestParams.fromJson(
          <String, Object?>{
            'name': name,
            'arguments': const <String, Object?>{},
          },
        ),
      );
    } on McpHttpStatusException catch (challenge) {
      await _authorizeForChallenge(
        coordinator,
        challenge,
        hasToken: true,
      );
      await runtime.client.callTool(
        McpCallToolRequestParams.fromJson(
          <String, Object?>{
            'name': name,
            'arguments': const <String, Object?>{},
          },
        ),
      );
    }
  } finally {
    await runtime.client.close();
  }
}

Future<void> _runScopeRetry(
  McpClient client,
  McpAuthorizationCoordinator coordinator,
) async {
  var hasToken = false;
  while (true) {
    try {
      await client.listTools(mcpPageRequest());
      return;
    } on McpHttpStatusException catch (challenge) {
      try {
        await _authorizeForChallenge(
          coordinator,
          challenge,
          hasToken: hasToken,
        );
        hasToken = true;
      } on McpAuthorizationException catch (error) {
        if (error.code == 'mcp_oauth_scope_retry_limit') return;
        rethrow;
      }
    }
  }
}

Future<void> _authorizeForChallenge(
  McpAuthorizationCoordinator coordinator,
  McpHttpStatusException challenge, {
  required bool hasToken,
}) {
  final header = challenge.header('www-authenticate');
  if (header == null) {
    throw StateError(
      'OAuth challenge ${challenge.statusCode} has no WWW-Authenticate.',
    );
  }
  return hasToken
      ? coordinator.authorizeAfterChallenge(
          redirectUri: _redirectUri,
          wwwAuthenticate: header,
        )
      : coordinator.authorize(
          redirectUri: _redirectUri,
          wwwAuthenticate: header,
        );
}

_ClientRuntime _createClient(
  Uri endpoint,
  http.Client packageClient, {
  bool elicitation = false,
  McpHttpAuthorizationProvider? authorizationProvider,
}) {
  final transport = McpHttpClientTransport(
    httpClient: McpPackageHttpClient(packageClient),
    endpoint: endpoint,
    authorizationProvider: authorizationProvider,
  );
  return _ClientRuntime(
    McpClient(
      transport: transport,
      capabilities: McpClientCapabilities(
        elicitationForm: elicitation,
      ),
      handlers: McpHandlerSet(
        requests: <String, McpRequestHandler>{
          if (elicitation)
            'elicitation/create': (invocation) {
              final params = invocation.params! as Map<String, Object?>;
              final schema = params['requestedSchema']! as Map<String, Object?>;
              final properties = schema['properties']! as Map<String, Object?>;
              return <String, Object?>{
                'action': 'accept',
                'content': <String, Object?>{
                  for (final entry in properties.entries)
                    if ((entry.value! as Map<String, Object?>)
                        .containsKey('default'))
                      entry.key:
                          (entry.value! as Map<String, Object?>)['default'],
                },
              };
            },
        },
      ),
      clientInfo: const <String, Object?>{
        'name': 'pigcode-ai-mcp-conformance-client',
        'version': '0.0.1',
      },
    ),
    transport,
  );
}

Future<void> _callFirstTool(
  McpClient client,
  Map<String, Object?> arguments,
) async {
  final tools = await client.listTools(mcpPageRequest());
  final definitions =
      (tools.toJson()! as Map<String, Object?>)['tools']! as List<Object?>;
  if (definitions.isEmpty) {
    throw StateError('Conformance server returned no tools.');
  }
  final name = (definitions.first! as Map<String, Object?>)['name']! as String;
  await client.callTool(
    McpCallToolRequestParams.fromJson(
      <String, Object?>{
        'name': name,
        'arguments': arguments,
      },
    ),
  );
}

Map<String, Object?> _conformanceContext() {
  final source = Platform.environment['MCP_CONFORMANCE_CONTEXT'];
  if (source == null || source.isEmpty) return const <String, Object?>{};
  return jsonDecode(source) as Map<String, Object?>;
}

final class _ClientRuntime {
  const _ClientRuntime(this.client, this.transport);

  final McpClient client;
  final McpHttpClientTransport transport;
}

final class _PackageAuthorizationHttpClient
    implements McpAuthorizationHttpClient {
  const _PackageAuthorizationHttpClient(this.client);

  final http.Client client;

  @override
  Future<McpAuthorizationHttpResponse> send(
    McpAuthorizationHttpRequest request,
  ) async {
    final outbound = http.Request(request.method, request.uri)
      ..followRedirects = false
      ..headers.addAll(request.headers)
      ..bodyBytes = request.body;
    final response = await client.send(outbound);
    final body = await response.stream.toBytes();
    return McpAuthorizationHttpResponse(
      statusCode: response.statusCode,
      headers: response.headers,
      body: body,
    );
  }
}

final class _MemoryAuthorizationStore implements McpAuthorizationStore {
  final Map<String, McpAccessToken> _tokens = <String, McpAccessToken>{};

  @override
  Future<McpAccessToken?> load(Uri resource) async =>
      _tokens[canonicalMcpResource(resource).toString()];

  @override
  Future<void> remove(Uri resource) async {
    _tokens.remove(canonicalMcpResource(resource).toString());
  }

  @override
  Future<void> save(McpAccessToken token) async {
    _tokens[canonicalMcpResource(token.resource).toString()] = token;
  }
}

final class _AutomatedBrowser
    implements McpBrowserLauncher, McpRedirectReceiver {
  _AutomatedBrowser(this.client);

  final http.Client client;
  Uri? _redirected;

  @override
  Future<void> open(Uri authorizationUri) async {
    final request = http.Request('GET', authorizationUri)
      ..followRedirects = false;
    final response = await client.send(request);
    await response.stream.drain<void>();
    final location = response.headers['location'];
    if (response.statusCode < 300 ||
        response.statusCode >= 400 ||
        location == null) {
      throw StateError(
        'Authorization endpoint did not return a redirect.',
      );
    }
    _redirected = authorizationUri.resolve(location);
  }

  @override
  Future<Uri> receive(Uri redirectUri) async {
    final redirected = _redirected;
    if (redirected == null) {
      throw StateError('Authorization redirect was not captured.');
    }
    return redirected;
  }
}

final class _ConformanceRegistrationProvider
    implements McpClientRegistrationProvider {
  const _ConformanceRegistrationProvider({
    required this.scenario,
    required this.context,
  });

  final String scenario;
  final Map<String, Object?> context;

  @override
  Uri? get clientMetadataDocument =>
      scenario == 'auth/basic-cimd' ? Uri.parse(_cimdClientId) : null;

  @override
  JsonObject dynamicRegistrationMetadata(Uri redirectUri) =>
      const <String, Object?>{
        'client_name': 'pigcode-ai-mcp-conformance-client',
      };

  @override
  Future<McpClientRegistration?> preRegistered(Uri issuer) async {
    if (scenario != 'auth/pre-registration') return null;
    return McpClientRegistration(
      clientId: context['client_id']! as String,
      clientSecret: context['client_secret']! as String,
      tokenEndpointAuthMethod: 'client_secret_basic',
      redirectUris: <Uri>[_redirectUri],
    );
  }
}

final class _RandomSource implements McpSecureRandom {
  final Random _random = Random.secure();

  @override
  List<int> bytes(int length) =>
      List<int>.generate(length, (_) => _random.nextInt(256));
}
