import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../sandbox/sandbox_errors.dart';
import '../sandbox/sandbox_policy.dart';

final class HostWorkspaceRoot {
  HostWorkspaceRoot({
    required this.name,
    required this.path,
    required this.access,
  }) {
    if (name.isEmpty || !File(path).isAbsolute) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'invalid-workspace-root',
      );
    }
  }

  final String name;
  final String path;
  final SandboxPathAccess access;
}

final class HostWorkspaceFileSystem {
  HostWorkspaceFileSystem(List<HostWorkspaceRoot> roots)
      : _roots = Map<String, HostWorkspaceRoot>.unmodifiable(
          <String, HostWorkspaceRoot>{
            for (final root in roots) root.name: root,
          },
        );

  final Map<String, HostWorkspaceRoot> _roots;

  String readText(String rootName, String relativePath) {
    final root = _root(rootName);
    final segments = _segments(relativePath);
    return utf8.decode(_NativeWorkspaceIo().read(root.path, segments));
  }

  void writeText(
    String rootName,
    String relativePath,
    String contents,
  ) {
    final root = _root(rootName);
    if (root.access != SandboxPathAccess.readWrite) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'read-only-root',
      );
    }
    final segments = _segments(relativePath);
    _NativeWorkspaceIo().write(root.path, segments, utf8.encode(contents));
  }

  HostWorkspaceRoot _root(String name) {
    final root = _roots[name];
    if (root == null) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'undeclared-root',
      );
    }
    return root;
  }

  List<String> _segments(String path) {
    String decoded;
    try {
      decoded = Uri.decodeComponent(path);
    } on FormatException {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'invalid-path-encoding',
      );
    }
    if (decoded.isEmpty ||
        File(decoded).isAbsolute ||
        decoded.contains('\\') ||
        decoded.contains('\u0000')) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'non-relative-path',
      );
    }
    final segments = decoded.split('/');
    if (segments.any(
      (segment) => segment.isEmpty || segment == '.' || segment == '..',
    )) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'path-traversal',
      );
    }
    return segments;
  }
}

final class _NativeWorkspaceIo {
  DynamicLibrary? _library;

  List<int> read(String root, List<String> segments) {
    final opened = _openPath(root, segments, write: false);
    try {
      _rejectHardLink(opened);
      final result = <int>[];
      final buffer = _calloc(8192);
      try {
        while (true) {
          final count = _read(opened, buffer, 8192);
          if (count == 0) break;
          if (count < 0) _deny('native-read-failed');
          result.addAll(buffer.asTypedList(count));
        }
      } finally {
        _free(buffer);
      }
      return result;
    } finally {
      _close(opened);
    }
  }

  void write(String root, List<String> segments, List<int> bytes) {
    // The final component is opened without O_TRUNC so the hard-link check
    // runs before any destructive change to the underlying inode.
    final opened = _openPath(root, segments, write: true);
    try {
      _rejectHardLink(opened);
      if (_ftruncate(opened, 0) != 0) _deny('native-truncate-failed');
      final buffer = _calloc(bytes.length);
      buffer.asTypedList(bytes.length).setAll(0, bytes);
      try {
        var offset = 0;
        while (offset < bytes.length) {
          final count = _write(
            opened,
            buffer + offset,
            bytes.length - offset,
          );
          if (count <= 0) _deny('native-write-failed');
          offset += count;
        }
      } finally {
        _free(buffer);
      }
    } finally {
      _close(opened);
    }
  }

  int _openPath(
    String root,
    List<String> segments, {
    required bool write,
  }) {
    var current = _openNative(root, _directory | _noFollow, 0);
    if (current < 0) _deny('root-open-denied');
    for (var index = 0; index < segments.length; index += 1) {
      final last = index == segments.length - 1;
      final flags =
          last ? (write ? _writeFlags : _noFollow) : _directory | _noFollow;
      final path = _nativeString(segments[index]);
      final next = _openAt(current, path, flags, 0x180);
      _free(path);
      _close(current);
      if (next < 0) _deny('component-open-denied');
      current = next;
    }
    return current;
  }

  void _rejectHardLink(int fd) {
    final stat = _calloc(256);
    try {
      if (_fstat(fd, stat) != 0) _deny('fstat-failed');
      final architecture = Platform.version.toLowerCase();
      final links = Platform.isMacOS
          ? (stat.cast<Uint16>() + 3).value
          : architecture.contains('arm64') || architecture.contains('aarch64')
              ? (stat.cast<Uint32>() + 5).value
              : (stat.cast<Uint64>() + 2).value;
      if (links > 1) _deny('hardlink-denied');
    } finally {
      _free(stat);
    }
  }

  // Linux open flags differ per architecture: x86_64 swaps the asm-generic
  // O_DIRECTORY/O_NOFOLLOW values used by arm64/aarch64 and riscv.
  bool get _linuxGenericAbi {
    final version = Platform.version.toLowerCase();
    return version.contains('arm64') ||
        version.contains('aarch64') ||
        version.contains('riscv');
  }

  int get _directory =>
      Platform.isMacOS ? 0x100000 : (_linuxGenericAbi ? 0x4000 : 0x10000);
  int get _noFollow =>
      Platform.isMacOS ? 0x100 : (_linuxGenericAbi ? 0x8000 : 0x20000);
  int get _writeFlags => 1 | _noFollow | (Platform.isMacOS ? 0x200 : 0x40);
  int get _atFdcwd => Platform.isLinux ? -100 : -2;

  int _openNative(String path, int flags, int mode) {
    final native = _nativeString(path);
    final result = _openAt(_atFdcwd, native, flags, mode);
    _free(native);
    return result;
  }

  int _openAt(int fd, Pointer<Uint8> path, int flags, int mode) {
    final openAt = _lib.lookupFunction<
        Int32 Function(Int32, Pointer<Uint8>, Int32, Uint32),
        int Function(int, Pointer<Uint8>, int, int)>('openat');
    return openAt(fd, path, flags, mode);
  }

  int _read(int fd, Pointer<Uint8> buffer, int size) {
    final read = _lib.lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)>('read');
    return read(fd, buffer, size);
  }

  int _write(int fd, Pointer<Uint8> buffer, int size) {
    final write = _lib.lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)>('write');
    return write(fd, buffer, size);
  }

  int _fstat(int fd, Pointer<Uint8> stat) {
    final fstat = _lib.lookupFunction<Int32 Function(Int32, Pointer<Uint8>),
        int Function(int, Pointer<Uint8>)>('fstat');
    return fstat(fd, stat);
  }

  int _ftruncate(int fd, int length) {
    final ftruncate = _lib.lookupFunction<Int32 Function(Int32, Int64),
        int Function(int, int)>('ftruncate');
    return ftruncate(fd, length);
  }

  void _close(int fd) {
    final close = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'close',
    );
    close(fd);
  }

  Pointer<Uint8> _nativeString(String value) {
    final bytes = <int>[...utf8.encode(value), 0];
    final pointer = _calloc(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<Uint8> _calloc(int size) {
    final calloc = _lib.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(size, 1);
    if (pointer == nullptr) _deny('native-allocation-failed');
    return pointer.cast<Uint8>();
  }

  void _free(Pointer<NativeType> pointer) {
    final free = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    free(pointer.cast<Void>());
  }

  DynamicLibrary get _lib => _library ??= DynamicLibrary.process();

  Never _deny(String rule) => throw HostCapabilityException(
        HostCapabilityError.pathDenied,
        rule,
      );
}
