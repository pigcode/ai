import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

const _defaultMaxRedirects = 10;

/// Redirect status codes defined by Fetch.
///
/// `300` and `304` deliberately are not redirect statuses even when a
/// `Location` header is present.
const redirectStatusCodes = <int>{301, 302, 303, 307, 308};

const _blockedRequestHeaders = <String>{
  'connection',
  'keep-alive',
  'te',
  'trailer',
  'transfer-encoding',
  'upgrade',
  'host',
  'forwarded',
  'proxy-authorization',
  'via',
  'x-forwarded-for',
  'x-forwarded-host',
  'x-forwarded-proto',
  'x-real-ip',
  'metadata',
  'metadata-flavor',
  'x-aws-ec2-metadata-token',
  'x-metadata-token',
  'cookie',
  'set-cookie',
};

/// A rejected or failed guarded download.
final class DownloadError implements Exception {
  const DownloadError({
    required this.url,
    this.statusCode,
    this.statusText,
    this.cause,
    String? message,
  }) : message = message ??
            (cause == null
                ? 'Failed to download $url: $statusCode $statusText'
                : 'Failed to download $url: $cause');

  final String url;
  final int? statusCode;
  final String? statusText;
  final Object? cause;
  final String message;

  @override
  String toString() => 'DownloadError: $message';
}

/// Returns whether [url] and [baseUrl] have the same scheme, host, and port.
///
/// Invalid or non-network URLs fail closed.
bool isSameOrigin(String url, String baseUrl) {
  final parsedUrl = _parseNetworkUri(url);
  final parsedBaseUrl = _parseNetworkUri(baseUrl);
  if (parsedUrl == null || parsedBaseUrl == null) {
    return false;
  }
  return parsedUrl.scheme.toLowerCase() == parsedBaseUrl.scheme.toLowerCase() &&
      parsedUrl.host.toLowerCase() == parsedBaseUrl.host.toLowerCase() &&
      _effectivePort(parsedUrl) == _effectivePort(parsedBaseUrl);
}

/// Returns a fresh header map without routing, proxy, metadata, cookie, or
/// hop-by-hop headers.
Map<String, String> sanitizeRequestHeaders(Map<String, String> input) {
  return <String, String>{
    for (final entry in input.entries)
      if (!_blockedRequestHeaders.contains(entry.key.toLowerCase()))
        entry.key: entry.value,
  };
}

/// Whether [statusCode] is one of the five redirect statuses followed by
/// [fetchWithValidatedRedirects].
bool isRedirectStatusCode(int statusCode) {
  return redirectStatusCodes.contains(statusCode);
}

/// Validates an untrusted download URL using portable literal/string checks.
///
/// This rejects non-network schemes (except inline `data:` URLs), localhost,
/// private, link-local, documentation, benchmarking, multicast, and reserved
/// literal IP targets. It intentionally does not resolve DNS. Applications
/// fetching untrusted URLs must additionally constrain network egress to
/// prevent DNS rebinding or a public hostname resolving to a private address.
void validateDownloadUrl(String url) {
  final parsed = Uri.tryParse(url);
  if (parsed == null || !parsed.hasScheme) {
    throw DownloadError(url: url, message: 'Invalid URL: $url');
  }

  final scheme = parsed.scheme.toLowerCase();
  if (scheme == 'data') {
    return;
  }
  if (scheme != 'http' && scheme != 'https') {
    throw DownloadError(
      url: url,
      message: 'URL scheme must be http, https, or data, got $scheme',
    );
  }
  if (!parsed.hasAuthority || parsed.host.isEmpty) {
    throw DownloadError(url: url, message: 'URL must have a hostname');
  }

  var hostname = parsed.host.toLowerCase();
  while (hostname.endsWith('.')) {
    hostname = hostname.substring(0, hostname.length - 1);
  }
  if (hostname.isEmpty) {
    throw DownloadError(url: url, message: 'URL must have a hostname');
  }
  if (hostname == 'localhost' ||
      hostname.endsWith('.local') ||
      hostname.endsWith('.localhost')) {
    throw DownloadError(
      url: url,
      message: 'URL with hostname $hostname is not allowed',
    );
  }

  final unbracketed = hostname.startsWith('[') && hostname.endsWith(']')
      ? hostname.substring(1, hostname.length - 1)
      : hostname;
  if (unbracketed.contains(':')) {
    if (_isPrivateIpv6(unbracketed)) {
      throw DownloadError(
        url: url,
        message: 'URL with IPv6 address $hostname is not allowed',
      );
    }
    return;
  }

  if (_isCanonicalIpv4(hostname)) {
    if (_isPrivateIpv4(hostname)) {
      throw DownloadError(
        url: url,
        message: 'URL with IP address $hostname is not allowed',
      );
    }
    return;
  }

  // Browsers accept several legacy numeric forms (integer, hexadecimal, and
  // octal-like IPv4). Dart URI parsing does not promise to canonicalize all of
  // them, so numeric-looking non-canonical hosts fail closed.
  if (_looksLikeNonCanonicalIpv4(hostname)) {
    throw DownloadError(
      url: url,
      message: 'URL with non-canonical IP address $hostname is not allowed',
    );
  }
}

/// Fetches [url] while validating every untrusted redirect target.
///
/// [trustedOrigin] may exempt a developer-configured provider origin from the
/// literal target guard, allowing intentional localhost/self-hosted endpoints.
/// [credentialedOrigin] limits caller headers to that origin; a first request
/// or redirect to another origin keeps only `User-Agent`.
Future<http.StreamedResponse> fetchWithValidatedRedirects({
  required String url,
  Map<String, String>? headers,
  CancellationSignal? cancellation,
  int maxRedirects = _defaultMaxRedirects,
  http.Client? client,
  String? credentialedOrigin,
  String? trustedOrigin,
}) async {
  if (maxRedirects < 0) {
    throw const InvalidArgumentError(
      argument: 'maxRedirects',
      message: 'maxRedirects must not be negative.',
    );
  }

  final ownsClient = client == null;
  final httpClient = client ?? http.Client();
  Map<String, String>? currentHeaders =
      headers == null ? null : sanitizeRequestHeaders(headers);
  var currentUrl = url;

  if (credentialedOrigin != null &&
      !isSameOrigin(currentUrl, credentialedOrigin)) {
    currentHeaders = _userAgentOnly(currentHeaders);
  }

  try {
    for (var redirectCount = 0;
        redirectCount <= maxRedirects;
        redirectCount++) {
      if (trustedOrigin == null || !isSameOrigin(currentUrl, trustedOrigin)) {
        validateDownloadUrl(currentUrl);
      }
      final currentUri = _parseNetworkUri(currentUrl);
      if (currentUri == null) {
        throw DownloadError(
            url: currentUrl, message: 'Invalid URL: $currentUrl');
      }

      final request = http.AbortableRequest(
        'GET',
        currentUri,
        abortTrigger: cancellation?.whenCancelled,
      )
        ..followRedirects = false
        ..headers.addAll(currentHeaders ?? const <String, String>{});

      final http.StreamedResponse response;
      try {
        response = await httpClient.send(request);
      } on http.RequestAbortedException {
        rethrow;
      } on Object catch (error) {
        throw DownloadError(url: currentUrl, cause: error);
      }

      final location = response.headers['location'];
      if (isRedirectStatusCode(response.statusCode) && location != null) {
        try {
          await response.stream.drain<void>();
        } on Object catch (error) {
          throw DownloadError(url: currentUrl, cause: error);
        }

        final Uri nextUri;
        try {
          nextUri = currentUri.resolve(location);
        } on FormatException catch (error) {
          throw DownloadError(url: currentUrl, cause: error);
        }
        final nextUrl = nextUri.toString();
        if (!isSameOrigin(nextUrl, currentUrl)) {
          currentHeaders = _userAgentOnly(currentHeaders);
        }
        currentUrl = nextUrl;
        continue;
      }

      if (!ownsClient) {
        return response;
      }
      return _closeClientWithResponse(response, httpClient);
    }

    throw DownloadError(
      url: url,
      message: 'Too many redirects (max $maxRedirects)',
    );
  } on Object {
    if (ownsClient) {
      httpClient.close();
    }
    rethrow;
  }
}

http.StreamedResponse _closeClientWithResponse(
  http.StreamedResponse response,
  http.Client client,
) {
  var closed = false;
  void closeOnce() {
    if (!closed) {
      closed = true;
      client.close();
    }
  }

  late final StreamSubscription<List<int>> subscription;
  final controller = StreamController<List<int>>();
  subscription = response.stream.listen(
    controller.add,
    onError: (Object error, StackTrace stackTrace) {
      closeOnce();
      controller.addError(error, stackTrace);
    },
    onDone: () {
      closeOnce();
      controller.close();
    },
  );
  controller
    ..onPause = subscription.pause
    ..onResume = subscription.resume
    ..onCancel = () async {
      await subscription.cancel();
      closeOnce();
    };

  return http.StreamedResponse(
    controller.stream,
    response.statusCode,
    contentLength: response.contentLength,
    request: response.request,
    headers: response.headers,
    isRedirect: response.isRedirect,
    persistentConnection: response.persistentConnection,
    reasonPhrase: response.reasonPhrase,
  );
}

Map<String, String>? _userAgentOnly(Map<String, String>? headers) {
  if (headers == null) {
    return null;
  }
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == 'user-agent') {
      return <String, String>{entry.key: entry.value};
    }
  }
  return <String, String>{};
}

Uri? _parseNetworkUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      !uri.hasScheme ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      (uri.scheme.toLowerCase() != 'http' &&
          uri.scheme.toLowerCase() != 'https')) {
    return null;
  }
  return uri;
}

int _effectivePort(Uri uri) {
  if (uri.hasPort) {
    return uri.port;
  }
  return uri.scheme.toLowerCase() == 'https' ? 443 : 80;
}

bool _isCanonicalIpv4(String hostname) {
  final parts = hostname.split('.');
  if (parts.length != 4) {
    return false;
  }
  for (final part in parts) {
    if (!RegExp(r'^(0|[1-9][0-9]{0,2})$').hasMatch(part)) {
      return false;
    }
    final value = int.parse(part);
    if (value > 255) {
      return false;
    }
  }
  return true;
}

bool _looksLikeNonCanonicalIpv4(String hostname) {
  return RegExp(
    r'^(?:(?:0[xX][0-9a-fA-F]+)|[0-9]+)(?:\.(?:(?:0[xX][0-9a-fA-F]+)|[0-9]+))*$',
  ).hasMatch(hostname);
}

bool _isPrivateIpv4(String ip) {
  final parts = ip.split('.').map(int.parse).toList(growable: false);
  final a = parts[0];
  final b = parts[1];
  final c = parts[2];

  return a == 0 ||
      a == 10 ||
      (a == 100 && b >= 64 && b <= 127) ||
      a == 127 ||
      (a == 169 && b == 254) ||
      (a == 172 && b >= 16 && b <= 31) ||
      (a == 192 && b == 0 && c == 0) ||
      (a == 192 && b == 0 && c == 2) ||
      (a == 192 && b == 168) ||
      (a == 198 && (b == 18 || b == 19)) ||
      (a == 198 && b == 51 && c == 100) ||
      (a == 203 && b == 0 && c == 113) ||
      a >= 224;
}

List<int>? _parseIpv6(String input) {
  var address = input.toLowerCase();
  final zoneIndex = address.indexOf('%');
  if (zoneIndex != -1) {
    address = address.substring(0, zoneIndex);
  }

  final halves = address.split('::');
  if (halves.length > 2) {
    return null;
  }

  List<int>? parseSegment(String segment) {
    if (segment.isEmpty) {
      return <int>[];
    }
    final groups = <int>[];
    final parts = segment.split(':');
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      if (part.contains('.')) {
        if (index != parts.length - 1 || !_isCanonicalIpv4(part)) {
          return null;
        }
        final ipv4 = part.split('.').map(int.parse).toList(growable: false);
        groups
          ..add((ipv4[0] << 8) | ipv4[1])
          ..add((ipv4[2] << 8) | ipv4[3]);
        continue;
      }
      if (!RegExp(r'^[0-9a-f]{1,4}$').hasMatch(part)) {
        return null;
      }
      groups.add(int.parse(part, radix: 16));
    }
    return groups;
  }

  final head = parseSegment(halves[0]);
  if (head == null) {
    return null;
  }
  if (halves.length == 2) {
    final tail = parseSegment(halves[1]);
    if (tail == null) {
      return null;
    }
    final fill = 8 - head.length - tail.length;
    if (fill < 0) {
      return null;
    }
    return <int>[...head, ...List<int>.filled(fill, 0), ...tail];
  }
  return head.length == 8 ? head : null;
}

bool _isPrivateIpv6(String ip) {
  final groups = _parseIpv6(ip);
  if (groups == null) {
    return true;
  }

  bool topZero(int count) {
    return groups.take(count).every((group) => group == 0);
  }

  if (topZero(7) && (groups[7] == 0 || groups[7] == 1)) {
    return true;
  }
  if ((groups[0] & 0xfe00) == 0xfc00 ||
      (groups[0] & 0xffc0) == 0xfe80 ||
      (groups[0] & 0xffc0) == 0xfec0 ||
      (groups[0] & 0xff00) == 0xff00 ||
      (groups[0] == 0x2001 && groups[1] == 0x0db8) ||
      (groups[0] == 0x3fff && (groups[1] & 0xf000) == 0)) {
    return true;
  }

  final embedsIpv4 = topZero(6) ||
      (topZero(5) && groups[5] == 0xffff) ||
      (topZero(4) && groups[4] == 0xffff && groups[5] == 0) ||
      (groups[0] == 0x0064 &&
          groups[1] == 0xff9b &&
          groups[2] == 0 &&
          groups[3] == 0 &&
          groups[4] == 0 &&
          groups[5] == 0) ||
      (groups[0] == 0x0064 && groups[1] == 0xff9b && groups[2] == 0x0001);
  if (!embedsIpv4) {
    return false;
  }

  final a = (groups[6] >> 8) & 0xff;
  final b = groups[6] & 0xff;
  final c = (groups[7] >> 8) & 0xff;
  final d = groups[7] & 0xff;
  return _isPrivateIpv4('$a.$b.$c.$d');
}
