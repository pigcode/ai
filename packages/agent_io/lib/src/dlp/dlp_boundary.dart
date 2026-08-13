import 'dart:convert';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import '../sandbox/sandbox_capability.dart';
import '../sandbox/sandbox_errors.dart';

enum DlpEnforcement { restricted, unsupported, notApplicable }

final class DlpCapabilityManifest {
  const DlpCapabilityManifest({
    required this.tcp,
    required this.udp,
    required this.dns,
    required this.abstractUnixSocket,
  });

  factory DlpCapabilityManifest.forSandbox(SandboxCapabilityReport report) {
    if (report.platform == SandboxPlatform.macosArm64) {
      return const DlpCapabilityManifest(
        tcp: DlpEnforcement.restricted,
        udp: DlpEnforcement.restricted,
        dns: DlpEnforcement.restricted,
        abstractUnixSocket: DlpEnforcement.notApplicable,
      );
    }
    if (report.platform == SandboxPlatform.linuxX64 ||
        report.platform == SandboxPlatform.linuxArm64) {
      final seccomp = report.seccompSupported == true;
      final tcp = (report.landlockAbi ?? 0) >= 4 && seccomp;
      return DlpCapabilityManifest(
        tcp: tcp ? DlpEnforcement.restricted : DlpEnforcement.unsupported,
        udp: seccomp ? DlpEnforcement.restricted : DlpEnforcement.unsupported,
        dns: tcp ? DlpEnforcement.restricted : DlpEnforcement.unsupported,
        abstractUnixSocket:
            seccomp ? DlpEnforcement.restricted : DlpEnforcement.unsupported,
      );
    }
    return const DlpCapabilityManifest(
      tcp: DlpEnforcement.unsupported,
      udp: DlpEnforcement.unsupported,
      dns: DlpEnforcement.unsupported,
      abstractUnixSocket: DlpEnforcement.unsupported,
    );
  }

  final DlpEnforcement tcp;
  final DlpEnforcement udp;
  final DlpEnforcement dns;
  final DlpEnforcement abstractUnixSocket;
}

List<int> redactContentLengthFrame(List<int> frame) {
  const separator = <int>[13, 10, 13, 10];
  final separatorIndex = _find(frame, separator);
  if (separatorIndex < 0) {
    _deny('dlp-framing-header-missing');
  }
  String header;
  try {
    header = ascii.decode(frame.sublist(0, separatorIndex));
  } on FormatException {
    _deny('dlp-framing-header-invalid');
  }
  final lengths = RegExp(
    r'^content-length:\s*([0-9]+)\s*$',
    caseSensitive: false,
    multiLine: true,
  ).allMatches(header).toList(growable: false);
  if (lengths.length != 1) {
    _deny('dlp-framing-content-length-invalid');
  }
  final body = frame.sublist(separatorIndex + separator.length);
  if (int.parse(lengths.single.group(1)!) != body.length) {
    _deny('dlp-framing-length-mismatch');
  }
  Object? decoded;
  try {
    decoded = jsonDecode(utf8.decode(body));
  } on FormatException {
    _deny('dlp-framing-json-invalid');
  }
  final redacted = _redact(decoded);
  validateSafePersistedJson(redacted);
  final output = utf8.encode(jsonEncode(redacted));
  return <int>[
    ...ascii.encode('Content-Length: ${output.length}\r\n\r\n'),
    ...output,
  ];
}

Object? _redact(Object? value) {
  if (value is Map<String, Object?>) {
    var redactedCount = 0;
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (_sensitiveKey.hasMatch(entry.key)) {
        redactedCount += 1;
      } else {
        result[entry.key] = _redact(entry.value);
      }
    }
    if (redactedCount > 0) result['redactedFields'] = redactedCount;
    return result;
  }
  if (value is List<Object?>) return value.map(_redact).toList();
  if (value is String &&
      _sensitiveValue.any((pattern) => pattern.hasMatch(value))) {
    return '<redacted>';
  }
  return value;
}

final _sensitiveKey = RegExp(
  r'authorization|credential|api[-_]?key|private[-_]?key|secret|token|password',
  caseSensitive: false,
);
final _sensitiveValue = <RegExp>[
  RegExp(r'\bBearer\s+\S+', caseSensitive: false),
  RegExp(r'sk-[A-Za-z0-9_-]{24,}'),
  RegExp(r'AKIA[0-9A-Z]{16}'),
  RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
];

int _find(List<int> bytes, List<int> pattern) {
  for (var index = 0; index <= bytes.length - pattern.length; index += 1) {
    var matches = true;
    for (var offset = 0; offset < pattern.length; offset += 1) {
      if (bytes[index + offset] != pattern[offset]) {
        matches = false;
        break;
      }
    }
    if (matches) return index;
  }
  return -1;
}

Never _deny(String rule) => throw HostCapabilityException(
      HostCapabilityError.networkDenied,
      rule,
    );
