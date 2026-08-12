enum HostCapabilityError {
  sandboxUnavailable,
  capabilityBelowMinimum,
  pathDenied,
  networkDenied,
  credentialDenied,
  processCleanupFailed,
  ptyUnavailable,
  gitPolicyDenied,
  shellInjectionRejected,
  unsafeModeRequired,
  unsupportedPlatform,
}

final class HostCapabilityException implements Exception {
  const HostCapabilityException(this.code, this.rule);

  final HostCapabilityError code;
  final String rule;

  @override
  String toString() => 'HostCapabilityException(${code.name}, rule: $rule)';
}
