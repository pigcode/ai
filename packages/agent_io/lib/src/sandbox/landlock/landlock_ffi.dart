import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import '../sandbox_errors.dart';
import '../sandbox_policy.dart';

enum LandlockPathType { file, directory }

final class LandlockFeatures {
  const LandlockFeatures({
    required this.abi,
    required this.fileSystem,
    required this.tcpNetwork,
    required this.deviceIoctl,
  });

  factory LandlockFeatures.fromAbi(int abi) => LandlockFeatures(
        abi: abi,
        fileSystem: abi >= 1,
        tcpNetwork: abi >= 4,
        deviceIoctl: abi >= 5,
      );

  final int abi;
  final bool fileSystem;
  final bool tcpNetwork;
  final bool deviceIoctl;
}

abstract final class LandlockFailure {
  static HostCapabilityException fromErrno(
    int errno, {
    required String operation,
  }) =>
      HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'landlock-$operation-errno-$errno',
      );
}

final class LandlockFfi {
  static const linuxStatxExpectedSize = 256;
  static const linuxStatxTailOffset = 144;
  static const linuxStatxTailWordCount = 14;

  static int get linuxStatxStructSize => sizeOf<_LinuxStatx>();

  static int get linuxStatxTailEnd =>
      linuxStatxTailOffset + linuxStatxTailWordCount * sizeOf<Uint64>();

  static void validateLinuxStatxLayout() {
    if (linuxStatxStructSize != linuxStatxExpectedSize ||
        linuxStatxTailEnd != linuxStatxExpectedSize) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-statx-layout-invalid',
      );
    }
  }

  static Uint8List encodeNativePath(String value) {
    if (value.contains('\u0000')) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'native-path-contains-nul',
      );
    }
    return Uint8List.fromList(<int>[...utf8.encode(value), 0]);
  }

  static void validatePolicyExpressibility(SandboxPolicy policy) {
    final roots = <_PolicyPath>[
      for (final root in policy.roots)
        _resolvePolicyPath(root.path, access: root.access),
    ];
    final denied = <_PolicyPath>[
      for (final deniedPath in policy.denyReadPaths)
        _resolvePolicyPath(deniedPath),
    ];
    final paths = <_PolicyPath>[...roots, ...denied];
    for (var leftIndex = 0; leftIndex < paths.length; leftIndex += 1) {
      for (var rightIndex = leftIndex + 1;
          rightIndex < paths.length;
          rightIndex += 1) {
        if (_overlaps(
              paths[leftIndex].canonical,
              paths[rightIndex].canonical,
            ) ||
            paths[leftIndex].identity == paths[rightIndex].identity) {
          throw const HostCapabilityException(
            HostCapabilityError.pathDenied,
            'landlock-path-overlap-or-identity-alias',
          );
        }
      }
    }
    if (policy.denyReadPaths.isNotEmpty) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-deny-read-unrepresentable',
      );
    }
    for (final parent in roots) {
      if (parent.access != SandboxPathAccess.readWrite) continue;
      final parentPath = parent.canonical;
      for (final child in roots) {
        if (identical(parent, child)) continue;
        final childPath = child.canonical;
        if (child.access == SandboxPathAccess.readOnly &&
            (childPath == parentPath || childPath.startsWith('$parentPath/'))) {
          throw const HostCapabilityException(
            HostCapabilityError.pathDenied,
            'landlock-nested-readonly-unrepresentable',
          );
        }
      }
    }
    if (policy.networkAllowlist.any((endpoint) => !endpoint.isPortOnly)) {
      throw const HostCapabilityException(
        HostCapabilityError.networkDenied,
        'landlock-host-constraint-unrepresentable',
      );
    }
  }

  static _PolicyPath _resolvePolicyPath(
    String value, {
    SandboxPathAccess? access,
  }) {
    if (!value.startsWith('/')) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-path-must-be-absolute',
      );
    }
    final normalized = _lexicalNormalize(value);
    final type = FileSystemEntity.typeSync(normalized, followLinks: true);
    if (type == FileSystemEntityType.notFound) {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-policy-path-must-exist',
      );
    }
    String canonical;
    try {
      canonical = type == FileSystemEntityType.directory
          ? Directory(normalized).resolveSymbolicLinksSync()
          : File(normalized).resolveSymbolicLinksSync();
    } on FileSystemException {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-path-identity-unavailable',
      );
    }
    return _PolicyPath(
      canonical: _lexicalNormalize(canonical),
      identity: Platform.isLinux
          ? LandlockFfi()._pathIdentity(canonical)
          : _lexicalNormalize(canonical),
      access: access,
    );
  }

  static String _lexicalNormalize(String value) {
    final segments = <String>[];
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isEmpty) {
          throw const HostCapabilityException(
            HostCapabilityError.pathDenied,
            'landlock-path-traverses-root',
          );
        }
        segments.removeLast();
      } else {
        segments.add(segment);
      }
    }
    return segments.isEmpty ? '/' : '/${segments.join('/')}';
  }

  static bool _overlaps(String left, String right) =>
      left == right || left.startsWith('$right/') || right.startsWith('$left/');

  String _pathIdentity(String value) {
    validateLinuxStatxLayout();
    final native = _nativeString(value);
    final stat = _callocStruct<_LinuxStatx>(sizeOf<_LinuxStatx>());
    try {
      final statx = _lib.lookupFunction<
          Int32 Function(
            Int32,
            Pointer<Uint8>,
            Int32,
            Uint32,
            Pointer<_LinuxStatx>,
          ),
          int Function(
            int,
            Pointer<Uint8>,
            int,
            int,
            Pointer<_LinuxStatx>,
          )>('statx');
      if (statx(-100, native, 0, 0x100, stat) != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.pathDenied,
          'landlock-path-identity-unavailable',
        );
      }
      return '${stat.ref.deviceMajor}:${stat.ref.deviceMinor}:'
          '${stat.ref.inode}';
    } on ArgumentError {
      throw const HostCapabilityException(
        HostCapabilityError.pathDenied,
        'landlock-statx-unavailable',
      );
    } finally {
      _free(native);
      _free(stat);
    }
  }

  static const _createRulesetVersion = 1;
  static const _rulePathBeneath = 1;
  static const _ruleNetPort = 2;
  static const _readFileAccess = 1 << 2;
  static const _readOnlyAccess = (1 << 0) | (1 << 2) | (1 << 3);
  static const _readWriteAccess = _readOnlyAccess |
      (1 << 1) |
      (1 << 4) |
      (1 << 5) |
      (1 << 6) |
      (1 << 7) |
      (1 << 8) |
      (1 << 9) |
      (1 << 10) |
      (1 << 11) |
      (1 << 12) |
      (1 << 13) |
      (1 << 14);
  static const _fileAccess =
      (1 << 0) | (1 << 1) | _readFileAccess | (1 << 14) | (1 << 15);
  static const _directoryOnlyAccess = (1 << 3) |
      (1 << 4) |
      (1 << 5) |
      (1 << 6) |
      (1 << 7) |
      (1 << 8) |
      (1 << 9) |
      (1 << 10) |
      (1 << 11) |
      (1 << 12) |
      (1 << 13);
  static const _networkAccess = (1 << 0) | (1 << 1);
  static const _deviceIoctlAccess = 1 << 15;
  static const _oPath = 0x200000;
  static const _oCloexec = 0x80000;
  static const _atEmptyPath = 0x1000;
  static const _statxType = 0x1;
  static const _fileTypeMask = 0xf000;
  static const _directoryType = 0x4000;

  static int get readOnlyAccessMask => _readOnlyAccess;
  static int get readWriteAccessMask => _readWriteAccess;
  static int get directoryOnlyAccessMask => _directoryOnlyAccess;
  static const runtimeFileAccessMask = _readFileAccess;
  static const _runtimeDirectoryDependencyPaths = <String>{
    '/bin',
    '/usr/bin',
    '/lib',
    '/lib64',
  };
  static const _runtimeFileDependencyPaths = <String>{
    '/etc/ld.so.cache',
    '/dev/null',
    '/proc/self/maps',
  };
  static const runtimeDependencyPaths = <String>{
    ..._runtimeDirectoryDependencyPaths,
    ..._runtimeFileDependencyPaths,
  };
  static const requiredRuntimeDependencyPaths = <String>{
    '/proc/self/maps',
  };

  static int allowedAccessForPathType(
    int requestedAccess,
    LandlockPathType pathType,
  ) =>
      pathType == LandlockPathType.directory
          ? requestedAccess
          : requestedAccess & _fileAccess;

  DynamicLibrary? _library;

  bool get isSupported => probeAbi() != null;

  int? probeAbi() {
    if (!Platform.isLinux) return null;
    final result = _createRuleset(
      nullptr,
      0,
      _createRulesetVersion,
    );
    return result < 0 ? null : result;
  }

  void apply(SandboxPolicy policy) {
    validatePolicyExpressibility(policy);
    final abi = probeAbi();
    if (abi == null) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'landlock-unavailable',
      );
    }
    if (abi < 4) {
      throw const HostCapabilityException(
        HostCapabilityError.capabilityBelowMinimum,
        'landlock-abi-minimum-4',
      );
    }

    final ruleset = _callocStruct<_LandlockRulesetAttr>(
      sizeOf<_LandlockRulesetAttr>(),
    );
    ruleset.ref
      ..handledAccessFs = _readWriteAccess |
          (policy.requiresPty && abi >= 5 ? _deviceIoctlAccess : 0)
      ..handledAccessNet = _networkAccess;
    final rulesetFd = _createRuleset(
      ruleset.cast<Void>(),
      sizeOf<_LandlockRulesetAttr>(),
      0,
    );
    _free(ruleset);
    if (rulesetFd < 0) _throwErrno('create-ruleset');

    try {
      for (final root in policy.roots) {
        _addPathRule(
          rulesetFd,
          root.path,
          root.access == SandboxPathAccess.readOnly
              ? _readOnlyAccess
              : _readWriteAccess,
        );
      }
      for (final dependency in runtimeDependencyPaths) {
        _addPathRule(
          rulesetFd,
          dependency,
          _runtimeDirectoryDependencyPaths.contains(dependency)
              ? _readOnlyAccess
              : runtimeFileAccessMask,
          runtimeDependency: true,
          allowMissing: !requiredRuntimeDependencyPaths.contains(dependency),
        );
      }
      for (final endpoint in policy.networkAllowlist) {
        _addNetworkRule(rulesetFd, endpoint.port);
      }
      if (_prctlNoNewPrivileges() != 0) _throwErrno('no-new-privileges');
      if (_restrictSelf(rulesetFd, 0) != 0) _throwErrno('restrict-self');
    } finally {
      _close(rulesetFd);
    }
  }

  void _addPathRule(
    int rulesetFd,
    String path,
    int access, {
    bool runtimeDependency = false,
    bool allowMissing = false,
  }) {
    final pathPointer = _nativeString(path);
    final parentFd = _open(pathPointer, _oPath | _oCloexec);
    final openErrno = parentFd < 0 ? _errno : 0;
    _free(pathPointer);
    if (parentFd < 0) {
      if (allowMissing && openErrno == 2) return;
      throw LandlockFailure.fromErrno(
        openErrno,
        operation:
            runtimeDependency ? 'open-runtime-dependency' : 'open-policy-root',
      );
    }
    try {
      final pathType = _pathTypeForFd(
        parentFd,
        runtimeDependency: runtimeDependency,
      );
      final attribute = _callocStruct<_LandlockPathBeneathAttr>(
        sizeOf<_LandlockPathBeneathAttr>(),
      );
      try {
        attribute.ref
          ..allowedAccess = allowedAccessForPathType(access, pathType)
          ..parentFd = parentFd;
        final result = _addRule(
          rulesetFd,
          _rulePathBeneath,
          attribute.cast<Void>(),
          0,
        );
        if (result != 0) {
          final errno = _errno;
          final category =
              runtimeDependency ? 'runtime-dependency' : pathType.name;
          throw LandlockFailure.fromErrno(
            errno,
            operation: 'add-$category-rule',
          );
        }
      } finally {
        _free(attribute);
      }
    } finally {
      _close(parentFd);
    }
  }

  LandlockPathType _pathTypeForFd(
    int fd, {
    required bool runtimeDependency,
  }) {
    validateLinuxStatxLayout();
    final emptyPath = _nativeString('');
    final stat = _callocStruct<_LinuxStatx>(sizeOf<_LinuxStatx>());
    final failureRule = runtimeDependency
        ? 'landlock-path-type-runtime-dependency-unavailable'
        : 'landlock-path-type-policy-root-unavailable';
    try {
      final statx = _lib.lookupFunction<
          Int32 Function(
            Int32,
            Pointer<Uint8>,
            Int32,
            Uint32,
            Pointer<_LinuxStatx>,
          ),
          int Function(
            int,
            Pointer<Uint8>,
            int,
            int,
            Pointer<_LinuxStatx>,
          )>('statx');
      if (statx(fd, emptyPath, _atEmptyPath, _statxType, stat) != 0 ||
          stat.ref.mask & _statxType == 0) {
        throw HostCapabilityException(
          HostCapabilityError.pathDenied,
          failureRule,
        );
      }
      return (stat.ref.mode & _fileTypeMask) == _directoryType
          ? LandlockPathType.directory
          : LandlockPathType.file;
    } on ArgumentError {
      throw HostCapabilityException(
        HostCapabilityError.pathDenied,
        failureRule,
      );
    } finally {
      _free(emptyPath);
      _free(stat);
    }
  }

  void _addNetworkRule(int rulesetFd, int port) {
    final attribute = _callocStruct<_LandlockNetPortAttr>(
      sizeOf<_LandlockNetPortAttr>(),
    );
    attribute.ref
      ..allowedAccess = _networkAccess
      ..port = port;
    final result = _addRule(
      rulesetFd,
      _ruleNetPort,
      attribute.cast<Void>(),
      0,
    );
    _free(attribute);
    if (result != 0) _throwErrno('add-network-rule');
  }

  DynamicLibrary get _lib => _library ??= DynamicLibrary.process();

  int _createRuleset(Pointer<Void> attr, int size, int flags) {
    final syscall = _lib.lookupFunction<
        Int64 Function(Int64, Pointer<Void>, Uint64, Uint32),
        int Function(int, Pointer<Void>, int, int)>('syscall');
    return syscall(_sysCreateRuleset, attr, size, flags);
  }

  int _addRule(int fd, int type, Pointer<Void> attr, int flags) {
    final syscall = _lib.lookupFunction<
        Int64 Function(Int64, Int32, Int32, Pointer<Void>, Uint32),
        int Function(int, int, int, Pointer<Void>, int)>('syscall');
    return syscall(_sysAddRule, fd, type, attr, flags);
  }

  int _restrictSelf(int fd, int flags) {
    final syscall = _lib.lookupFunction<Int64 Function(Int64, Int32, Uint32),
        int Function(int, int, int)>('syscall');
    return syscall(_sysRestrictSelf, fd, flags);
  }

  int _prctlNoNewPrivileges() {
    final prctl = _lib.lookupFunction<
        Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
        int Function(int, int, int, int, int)>('prctl');
    return prctl(38, 1, 0, 0, 0);
  }

  int _open(Pointer<Uint8> path, int flags) {
    final open = _lib.lookupFunction<Int32 Function(Pointer<Uint8>, Int32),
        int Function(Pointer<Uint8>, int)>('open');
    return open(path, flags);
  }

  void _close(int fd) {
    final close = _lib.lookupFunction<Int32 Function(Int32), int Function(int)>(
      'close',
    );
    close(fd);
  }

  int get _errno {
    final location = _lib.lookupFunction<Pointer<Int32> Function(),
        Pointer<Int32> Function()>('__errno_location');
    return location().value;
  }

  Never _throwErrno(String operation) =>
      throw LandlockFailure.fromErrno(_errno, operation: operation);

  int get _sysCreateRuleset => 444;
  int get _sysAddRule => 445;
  int get _sysRestrictSelf => 446;

  Pointer<T> _callocStruct<T extends NativeType>(int size) {
    final calloc = _lib.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(1, size);
    if (pointer == nullptr) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'native-allocation-failed',
      );
    }
    return pointer.cast<T>();
  }

  Pointer<Uint8> _nativeString(String value) {
    final bytes = encodeNativePath(value);
    final pointer = _callocBytes(bytes.length);
    pointer.asTypedList(bytes.length).setAll(0, bytes);
    return pointer;
  }

  Pointer<Uint8> _callocBytes(int length) {
    final calloc = _lib.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(length, 1);
    if (pointer == nullptr) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'native-allocation-failed',
      );
    }
    return pointer.cast<Uint8>();
  }

  void _free(Pointer<NativeType> pointer) {
    final free = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    free(pointer.cast<Void>());
  }
}

final class _LandlockRulesetAttr extends Struct {
  @Uint64()
  external int handledAccessFs;

  @Uint64()
  external int handledAccessNet;
}

final class _LandlockPathBeneathAttr extends Struct {
  @Uint64()
  external int allowedAccess;

  @Int32()
  external int parentFd;

  @Uint32()
  external int reserved;
}

final class _LandlockNetPortAttr extends Struct {
  @Uint64()
  external int allowedAccess;

  @Uint64()
  external int port;
}

final class _LinuxStatxTimestamp extends Struct {
  @Int64()
  external int seconds;

  @Uint32()
  external int nanoseconds;

  @Int32()
  external int reserved;
}

final class _LinuxStatx extends Struct {
  @Uint32()
  external int mask;
  @Uint32()
  external int blockSize;
  @Uint64()
  external int attributes;
  @Uint32()
  external int linkCount;
  @Uint32()
  external int userId;
  @Uint32()
  external int groupId;
  @Uint16()
  external int mode;
  @Uint16()
  external int spare;
  @Uint64()
  external int inode;
  @Uint64()
  external int size;
  @Uint64()
  external int blocks;
  @Uint64()
  external int attributesMask;
  external _LinuxStatxTimestamp accessTime;
  external _LinuxStatxTimestamp birthTime;
  external _LinuxStatxTimestamp changeTime;
  external _LinuxStatxTimestamp modificationTime;
  @Uint32()
  external int deviceSpecialMajor;
  @Uint32()
  external int deviceSpecialMinor;
  @Uint32()
  external int deviceMajor;
  @Uint32()
  external int deviceMinor;
  @Array(LandlockFfi.linuxStatxTailWordCount)
  external Array<Uint64> tail;
}

final class _PolicyPath {
  const _PolicyPath({
    required this.canonical,
    required this.identity,
    required this.access,
  });

  final String canonical;
  final String identity;
  final SandboxPathAccess? access;
}
