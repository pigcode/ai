import 'dart:ffi';
import 'dart:io';

import '../sandbox_errors.dart';

final class SeccompFfi {
  static const blockedCapabilityNames = <String>{
    'ptrace',
    'socket',
    'socketpair',
    'connect',
    'bind',
    'setsid',
    'setpgid',
    'unshare',
  };
  static const _filterMode = 1;
  static const _bpfLoadWordAbsolute = 0x20;
  static const _bpfJumpEqual = 0x15;
  static const _bpfReturn = 0x06;
  static const _returnAllow = 0x7fff0000;
  static const _returnErrno = 0x00050000;
  static const _returnKillProcess = 0x80000000;
  static const _eperm = 1;

  DynamicLibrary? _library;

  bool get isSupported {
    if (!Platform.isLinux) return false;
    final prctl = _lib.lookupFunction<
        Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
        int Function(int, int, int, int, int)>('prctl');
    return prctl(21, 0, 0, 0, 0) >= 0;
  }

  void apply() {
    if (!Platform.isLinux) {
      throw const HostCapabilityException(
        HostCapabilityError.unsupportedPlatform,
        'seccomp-linux-only',
      );
    }
    final blockedSyscalls = _blockedSyscalls;
    final filterCount = 5 + blockedSyscalls.length * 2;
    final filters =
        _calloc(filterCount, sizeOf<_SockFilter>()).cast<_SockFilter>();
    final program = _calloc(1, sizeOf<_SockFprog>()).cast<_SockFprog>();
    try {
      _setFilter(filters + 0, _bpfLoadWordAbsolute, 0, 0, 4);
      _setFilter(filters + 1, _bpfJumpEqual, 1, 0, _auditArchitecture);
      _setFilter(filters + 2, _bpfReturn, 0, 0, _returnKillProcess);
      _setFilter(filters + 3, _bpfLoadWordAbsolute, 0, 0, 0);
      var index = 4;
      for (final syscall in blockedSyscalls) {
        _setFilter(filters + index, _bpfJumpEqual, 0, 1, syscall);
        _setFilter(
          filters + index + 1,
          _bpfReturn,
          0,
          0,
          _returnErrno | _eperm,
        );
        index += 2;
      }
      _setFilter(filters + index, _bpfReturn, 0, 0, _returnAllow);
      program.ref
        ..length = filterCount
        ..filters = filters;
      if (_prctlNoNewPrivileges() != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.sandboxUnavailable,
          'seccomp-no-new-privileges-failed',
        );
      }
      if (_seccomp(_filterMode, 0, program.cast<Void>()) != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.sandboxUnavailable,
          'seccomp-filter-apply-failed',
        );
      }
    } finally {
      _free(program);
      _free(filters);
    }
  }

  void _setFilter(
    Pointer<_SockFilter> pointer,
    int code,
    int jumpTrue,
    int jumpFalse,
    int value,
  ) {
    pointer.ref
      ..code = code
      ..jumpTrue = jumpTrue
      ..jumpFalse = jumpFalse
      ..value = value;
  }

  int _prctlNoNewPrivileges() {
    final prctl = _lib.lookupFunction<
        Int32 Function(Int32, Uint64, Uint64, Uint64, Uint64),
        int Function(int, int, int, int, int)>('prctl');
    return prctl(38, 1, 0, 0, 0);
  }

  int _seccomp(int operation, int flags, Pointer<Void> arguments) {
    final syscall = _lib.lookupFunction<
        Int64 Function(Int64, Uint32, Uint32, Pointer<Void>),
        int Function(int, int, int, Pointer<Void>)>('syscall');
    return syscall(_seccompSyscall, operation, flags, arguments);
  }

  bool get _arm64 => Abi.current() == Abi.linuxArm64;

  List<int> get _blockedSyscalls => _arm64
      ? const <int>[117, 198, 199, 203, 200, 157, 154, 97]
      : const <int>[101, 41, 53, 42, 49, 112, 109, 272];

  int get _auditArchitecture => _arm64 ? 0xc00000b7 : 0xc000003e;
  int get _seccompSyscall => _arm64 ? 277 : 317;

  DynamicLibrary get _lib => _library ??= DynamicLibrary.process();

  Pointer<Void> _calloc(int count, int size) {
    final calloc = _lib.lookupFunction<Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(count, size);
    if (pointer == nullptr) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'native-allocation-failed',
      );
    }
    return pointer;
  }

  void _free(Pointer<NativeType> pointer) {
    final free = _lib.lookupFunction<Void Function(Pointer<Void>),
        void Function(Pointer<Void>)>('free');
    free(pointer.cast<Void>());
  }
}

final class _SockFilter extends Struct {
  @Uint16()
  external int code;

  @Uint8()
  external int jumpTrue;

  @Uint8()
  external int jumpFalse;

  @Uint32()
  external int value;
}

final class _SockFprog extends Struct {
  @Uint16()
  external int length;

  external Pointer<_SockFilter> filters;
}
