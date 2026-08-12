import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'sandbox_errors.dart';

final Object _trustedProbeProvenance = Object();

enum SandboxPlatform {
  macosArm64,
  linuxX64,
  linuxArm64,
  unsupported;

  static SandboxPlatform get current {
    if (Platform.isMacOS) {
      return Platform.version.toLowerCase().contains('arm64')
          ? SandboxPlatform.macosArm64
          : SandboxPlatform.unsupported;
    }
    if (Platform.isLinux) {
      final architecture = Platform.version.toLowerCase();
      return architecture.contains('arm64') || architecture.contains('aarch64')
          ? SandboxPlatform.linuxArm64
          : SandboxPlatform.linuxX64;
    }
    return SandboxPlatform.unsupported;
  }
}

final class SandboxCapabilityReport {
  SandboxCapabilityReport.untrusted({
    required this.platform,
    required this.backend,
    required this.available,
    required this.minimumSatisfied,
    this.landlockAbi,
    this.seccompSupported,
    this.sandboxExecPresent,
    this.labels = const <String>{},
  }) : _probeProvenance = null;

  SandboxCapabilityReport._probed({
    required this.platform,
    required this.backend,
    required this.available,
    required this.minimumSatisfied,
    this.landlockAbi,
    this.seccompSupported,
    this.sandboxExecPresent,
  })  : labels = const <String>{},
        _probeProvenance = _trustedProbeProvenance;

  final SandboxPlatform platform;
  final String backend;
  final bool available;
  final bool minimumSatisfied;
  final int? landlockAbi;
  final bool? seccompSupported;
  final bool? sandboxExecPresent;
  final Set<String> labels;
  final Object? _probeProvenance;

  String get digest => sha256
      .convert(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'available': available,
            'backend': backend,
            'labels': labels.toList()..sort(),
            'landlockAbi': landlockAbi,
            'minimumSatisfied': minimumSatisfied,
            'platform': platform.name,
            'sandboxExecPresent': sandboxExecPresent,
            'seccompSupported': seccompSupported,
          }),
        ),
      )
      .toString();

  bool get productionReady =>
      available &&
      minimumSatisfied &&
      identical(_probeProvenance, _trustedProbeProvenance) &&
      !labels.contains('unsafe/dev-only') &&
      platform != SandboxPlatform.unsupported;

  void requireProductionReady() {
    if (productionReady) {
      return;
    }
    if (platform == SandboxPlatform.unsupported) {
      throw const HostCapabilityException(
        HostCapabilityError.unsupportedPlatform,
        'unsupported-platform',
      );
    }
    if (landlockAbi != null && landlockAbi! < 4) {
      throw const HostCapabilityException(
        HostCapabilityError.capabilityBelowMinimum,
        'landlock-abi-minimum-4',
      );
    }
    if (sandboxExecPresent == true && !minimumSatisfied) {
      throw const HostCapabilityException(
        HostCapabilityError.capabilityBelowMinimum,
        'macos-minimum-13',
      );
    }
    throw const HostCapabilityException(
      HostCapabilityError.sandboxUnavailable,
      'production-sandbox-unavailable',
    );
  }
}

final class SandboxCapabilityProbe {
  SandboxCapabilityProbe({
    SandboxPlatform? platform,
    bool Function()? sandboxExecExists,
    int Function()? macosMajorVersion,
    int? Function()? landlockAbi,
    bool Function()? seccompSupported,
  })  : platform = platform ?? SandboxPlatform.current,
        _sandboxExecExists = sandboxExecExists ??
            (() => File('/usr/bin/sandbox-exec').existsSync()),
        _macosMajorVersion = macosMajorVersion ?? _currentMacosMajorVersion,
        _landlockAbi = landlockAbi ?? (() => null),
        _seccompSupported = seccompSupported ?? (() => false);

  final SandboxPlatform platform;
  final bool Function() _sandboxExecExists;
  final int Function() _macosMajorVersion;
  final int? Function() _landlockAbi;
  final bool Function() _seccompSupported;

  SandboxCapabilityReport probe() {
    return switch (platform) {
      SandboxPlatform.macosArm64 => _probeSeatbelt(),
      SandboxPlatform.linuxX64 ||
      SandboxPlatform.linuxArm64 =>
        _probeLandlock(),
      SandboxPlatform.unsupported => SandboxCapabilityReport._probed(
          platform: platform,
          backend: 'none',
          available: false,
          minimumSatisfied: false,
        ),
    };
  }

  SandboxCapabilityReport _probeSeatbelt() {
    final present = _sandboxExecExists();
    final minimumSatisfied = _macosMajorVersion() >= 13;
    return SandboxCapabilityReport._probed(
      platform: platform,
      backend: 'seatbelt',
      available: present && minimumSatisfied,
      minimumSatisfied: minimumSatisfied,
      sandboxExecPresent: present,
    );
  }

  SandboxCapabilityReport _probeLandlock() {
    final abi = _landlockAbi();
    final seccomp = _seccompSupported();
    final minimumSatisfied = abi != null && abi >= 4;
    return SandboxCapabilityReport._probed(
      platform: platform,
      backend: 'landlock-seccomp',
      available: minimumSatisfied && seccomp,
      minimumSatisfied: minimumSatisfied,
      landlockAbi: abi,
      seccompSupported: seccomp,
    );
  }

  static int _currentMacosMajorVersion() {
    final match = RegExp(r'\d+').firstMatch(Platform.operatingSystemVersion);
    return match == null ? 0 : int.parse(match.group(0)!);
  }
}
