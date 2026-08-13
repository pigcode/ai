import 'dart:io';

import '../sandbox_errors.dart';
import '../sandbox_policy.dart';

abstract final class SbplProfile {
  static String generate(
    SandboxPolicy policy, {
    List<String> trustedRuntimeReadPaths = const <String>[],
  }) {
    final lines = <String>[
      '(version 1)',
      '(deny default)',
      '(import "system.sb")',
      '(allow process*)',
      '(allow sysctl-read)',
    ];

    for (final root in policy.roots) {
      final path = _string(_canonicalPath(root.path));
      for (final ancestor in _ancestors(path)) {
        lines.add('(allow file-read-metadata (literal "$ancestor"))');
      }
      lines.add('(allow file-read* (subpath "$path"))');
      if (root.access == SandboxPathAccess.readWrite) {
        lines.add('(allow file-write* (subpath "$path"))');
      }
    }
    for (final runtimePath in trustedRuntimeReadPaths) {
      final path = _string(_canonicalPath(runtimePath));
      for (final ancestor in _ancestors(path)) {
        lines.add('(allow file-read-metadata (literal "$ancestor"))');
      }
      final type = FileSystemEntity.typeSync(runtimePath);
      lines.add(
        type == FileSystemEntityType.directory
            ? '(allow file-read* (subpath "$path"))'
            : '(allow file-read* (literal "$path"))',
      );
    }
    if (policy.requiresPty) {
      lines
        ..add(
          '(allow file-read* file-write* file-ioctl '
          '(literal "/dev/null") (literal "/dev/ptmx") '
          '(literal "/dev/tty") (regex #"^/dev/ttys[0-9]+\$"))',
        )
        ..add('(allow pseudo-tty)');
    }

    for (final endpoint in policy.networkAllowlist) {
      if (endpoint.host != 'localhost') {
        throw const HostCapabilityException(
          HostCapabilityError.networkDenied,
          'seatbelt-exact-host-unrepresentable',
        );
      }
      lines.add(
        '(allow network-outbound '
        '(remote ip "${endpoint.host}:${endpoint.port}"))',
      );
      lines.add(
        '(allow network-bind '
        '(local tcp "*:${endpoint.port}"))',
      );
      lines.add(
        '(allow network-inbound '
        '(local tcp "*:${endpoint.port}"))',
      );
    }
    for (final path in policy.denyReadPaths) {
      lines.add(
        '(deny file-read* (subpath "${_string(_canonicalPath(path))}"))',
      );
    }
    for (final root in policy.roots) {
      if (root.access == SandboxPathAccess.readOnly) {
        lines.add(
          '(deny file-write* '
          '(subpath "${_string(_canonicalPath(root.path))}"))',
        );
      }
    }
    return '${lines.join('\n')}\n';
  }

  static String _canonicalPath(String path) {
    try {
      return File(path).resolveSymbolicLinksSync();
    } on FileSystemException {
      return path;
    }
  }

  static Iterable<String> _ancestors(String path) sync* {
    var current = Directory(path).parent.path;
    while (current != '/' && current != '.') {
      yield _string(current);
      current = Directory(current).parent.path;
    }
  }

  static String _string(String value) {
    final escaped = StringBuffer();
    for (final rune in value.runes) {
      switch (rune) {
        case 0x22:
          escaped.write(r'\"');
        case 0x5c:
          escaped.write(r'\\');
        case 0x0a:
          escaped.write(r'\n');
        case 0x0d:
          escaped.write(r'\r');
        case 0x09:
          escaped.write(r'\t');
        default:
          if (rune < 0x20 || rune == 0x7f) {
            throw const HostCapabilityException(
              HostCapabilityError.pathDenied,
              'sbpl-path-unrepresentable',
            );
          }
          escaped.writeCharCode(rune);
      }
    }
    return escaped.toString();
  }
}
