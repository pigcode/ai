import 'sandbox_errors.dart';

enum SandboxPathAccess { readOnly, readWrite }

final class SandboxPathRule {
  SandboxPathRule({required this.path, required this.access}) {
    if (path.isEmpty || path.contains('\u0000')) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'invalid-root',
      );
    }
  }

  final String path;
  final SandboxPathAccess access;
}

final class SandboxNetworkEndpoint {
  SandboxNetworkEndpoint({required this.host, required this.port}) {
    if (host.isEmpty ||
        (host.contains('*') && host != '*') ||
        host.contains('/') ||
        host.contains(RegExp(r'\s')) ||
        port < 1 ||
        port > 65535) {
      throw const HostCapabilityException(
        HostCapabilityError.networkDenied,
        'invalid-network-allowlist-entry',
      );
    }
  }

  final String host;
  final int port;

  bool get isPortOnly => host == '*';

  String get authority => '$host:$port';
}

final class SandboxPolicy {
  SandboxPolicy({
    required List<SandboxPathRule> roots,
    List<SandboxNetworkEndpoint> networkAllowlist =
        const <SandboxNetworkEndpoint>[],
    List<String> denyReadPaths = const <String>[],
    this.requiresPty = false,
  })  : roots = List<SandboxPathRule>.unmodifiable(roots),
        networkAllowlist = List<SandboxNetworkEndpoint>.unmodifiable(
          networkAllowlist,
        ),
        denyReadPaths = List<String>.unmodifiable(denyReadPaths) {
    if (roots.isEmpty) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'explicit-root-required',
      );
    }
    if (denyReadPaths.any((path) => path.isEmpty || path.contains('\u0000'))) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'invalid-deny-read-path',
      );
    }
  }

  final List<SandboxPathRule> roots;
  final List<SandboxNetworkEndpoint> networkAllowlist;
  final List<String> denyReadPaths;
  final bool requiresPty;
}
