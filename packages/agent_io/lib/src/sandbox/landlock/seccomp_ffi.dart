import 'dart:ffi';
import 'dart:io';

import '../sandbox_errors.dart';
import 'seccomp_policy.dart';

final class SeccompFfi {
  static const blockedCapabilityNames = <String>{
    'ptrace',
    'socket(non-inet-or-non-stream)',
    'setsid',
    'setpgid',
    'unshare',
  };
  static const _filterMode = 1;

  DynamicLibrary? _library;

  bool get isSupported {
    if (!Platform.isLinux) return false;
    if (_architecture == null || !_hasExpectedFilterLayout) return false;
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
    final architecture = _architecture;
    if (architecture == null) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seccomp-unsupported-architecture',
      );
    }
    if (!_hasExpectedFilterLayout) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seccomp-bpf-layout-invalid',
      );
    }
    final policy = SeccompPolicy.forArchitecture(architecture);
    final instructions = policy.buildProgram().instructions;
    final filterCount = instructions.length;
    final filters =
        _calloc(filterCount, sizeOf<_SockFilter>()).cast<_SockFilter>();
    final program = _calloc(1, sizeOf<_SockFprog>()).cast<_SockFprog>();
    try {
      for (var index = 0; index < instructions.length; index += 1) {
        final instruction = instructions[index];
        _setFilter(
          filters + index,
          instruction.code,
          instruction.jumpTrue,
          instruction.jumpFalse,
          instruction.value,
        );
      }
      program.ref
        ..length = filterCount
        ..filters = filters;
      if (_prctlNoNewPrivileges() != 0) {
        throw const HostCapabilityException(
          HostCapabilityError.sandboxUnavailable,
          'seccomp-no-new-privileges-failed',
        );
      }
      if (_seccomp(
            policy.seccompSystemCall,
            _filterMode,
            0,
            program.cast<Void>(),
          ) !=
          0) {
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

  int _seccomp(
    int systemCall,
    int operation,
    int flags,
    Pointer<Void> arguments,
  ) {
    final syscall = _lib.lookupFunction<
        Int64 Function(Int64, Uint32, Uint32, Pointer<Void>),
        int Function(int, int, int, Pointer<Void>)>('syscall');
    return syscall(systemCall, operation, flags, arguments);
  }

  SeccompArchitecture? get _architecture {
    final abi = Abi.current();
    if (abi == Abi.linuxX64) return SeccompArchitecture.linuxX64;
    if (abi == Abi.linuxArm64) return SeccompArchitecture.linuxArm64;
    return null;
  }

  bool get _hasExpectedFilterLayout =>
      sizeOf<IntPtr>() == 8 &&
      sizeOf<_SockFilter>() == 8 &&
      sizeOf<_SockFprog>() == 16;

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
