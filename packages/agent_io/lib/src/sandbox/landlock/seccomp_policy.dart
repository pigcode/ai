enum SeccompArchitecture { linuxX64, linuxArm64 }

enum SeccompFilterAction { allow, permissionDenied, killProcess }

final class SeccompFilterInstruction {
  const SeccompFilterInstruction({
    required this.code,
    required this.jumpTrue,
    required this.jumpFalse,
    required this.value,
  });

  final int code;
  final int jumpTrue;
  final int jumpFalse;
  final int value;
}

final class SeccompFilterProgram {
  const SeccompFilterProgram(this.instructions);

  final List<SeccompFilterInstruction> instructions;

  SeccompFilterAction evaluate({
    required int auditArchitecture,
    required int systemCall,
    List<int> arguments = const <int>[],
  }) {
    var accumulator = 0;
    var programCounter = 0;
    var remainingSteps = instructions.length * 2;
    while (programCounter < instructions.length && remainingSteps-- > 0) {
      final instruction = instructions[programCounter];
      switch (instruction.code) {
        case SeccompPolicy.bpfLoadWordAbsolute:
          accumulator = _wordAt(
            instruction.value,
            auditArchitecture: auditArchitecture,
            systemCall: systemCall,
            arguments: arguments,
          );
          programCounter += 1;
        case SeccompPolicy.bpfJumpEqual:
          programCounter += 1 +
              (accumulator == instruction.value
                  ? instruction.jumpTrue
                  : instruction.jumpFalse);
        case SeccompPolicy.bpfJumpGreaterOrEqual:
          programCounter += 1 +
              (accumulator >= instruction.value
                  ? instruction.jumpTrue
                  : instruction.jumpFalse);
        case SeccompPolicy.bpfAnd:
          accumulator &= instruction.value;
          programCounter += 1;
        case SeccompPolicy.bpfReturn:
          return switch (instruction.value) {
            SeccompPolicy.returnAllow => SeccompFilterAction.allow,
            SeccompPolicy.returnPermissionDenied =>
              SeccompFilterAction.permissionDenied,
            SeccompPolicy.returnKillProcess => SeccompFilterAction.killProcess,
            _ => throw StateError(
                'Unsupported seccomp return value ${instruction.value}.',
              ),
          };
        default:
          throw StateError(
            'Unsupported classic BPF opcode ${instruction.code}.',
          );
      }
    }
    throw StateError('Seccomp filter did not terminate.');
  }

  static int _wordAt(
    int offset, {
    required int auditArchitecture,
    required int systemCall,
    required List<int> arguments,
  }) {
    final value = switch (offset) {
      SeccompPolicy.systemCallOffset => systemCall,
      SeccompPolicy.auditArchitectureOffset => auditArchitecture,
      SeccompPolicy.argument0Offset => arguments.isEmpty ? 0 : arguments[0],
      SeccompPolicy.argument1Offset => arguments.length < 2 ? 0 : arguments[1],
      _ => throw StateError('Unsupported seccomp_data offset $offset.'),
    };
    return value & 0xffffffff;
  }
}

final class SeccompPolicy {
  const SeccompPolicy._({
    required this.architecture,
    required this.auditArchitecture,
    required this.seccompSystemCall,
    required this.ptraceSystemCall,
    required this.socketSystemCall,
    required this.socketPairSystemCall,
    required this.connectSystemCall,
    required this.bindSystemCall,
    required this.setsidSystemCall,
    required this.setpgidSystemCall,
    required this.unshareSystemCall,
  });

  // Linux UAPI struct seccomp_data:
  // int nr; __u32 arch; __u64 instruction_pointer; __u64 args[6].
  static const systemCallOffset = 0;
  static const auditArchitectureOffset = 4;
  static const argument0Offset = 16;
  static const argument1Offset = 24;

  static const bpfLoadWordAbsolute = 0x20;
  static const bpfJumpEqual = 0x15;
  static const bpfJumpGreaterOrEqual = 0x35;
  static const bpfAnd = 0x54;
  static const bpfReturn = 0x06;

  static const returnAllow = 0x7fff0000;
  static const returnPermissionDenied = 0x00050001;
  static const returnKillProcess = 0x80000000;

  static const addressFamilyUnix = 1;
  static const addressFamilyInet = 2;
  static const addressFamilyInet6 = 10;
  static const addressFamilyPacket = 17;
  static const socketStream = 1;
  static const socketDatagram = 2;
  static const socketRaw = 3;
  static const socketTypeMask = 0xf;
  static const socketNonblock = 1 << 11;
  static const socketCloexec = 1 << 19;
  static const x32SystemCallBit = 0x40000000;

  static const _linuxX64 = SeccompPolicy._(
    architecture: SeccompArchitecture.linuxX64,
    auditArchitecture: 0xc000003e,
    seccompSystemCall: 317,
    ptraceSystemCall: 101,
    socketSystemCall: 41,
    socketPairSystemCall: 53,
    connectSystemCall: 42,
    bindSystemCall: 49,
    setsidSystemCall: 112,
    setpgidSystemCall: 109,
    unshareSystemCall: 272,
  );

  static const _linuxArm64 = SeccompPolicy._(
    architecture: SeccompArchitecture.linuxArm64,
    auditArchitecture: 0xc00000b7,
    seccompSystemCall: 277,
    ptraceSystemCall: 117,
    socketSystemCall: 198,
    socketPairSystemCall: 199,
    connectSystemCall: 203,
    bindSystemCall: 200,
    setsidSystemCall: 157,
    setpgidSystemCall: 154,
    unshareSystemCall: 97,
  );

  static SeccompPolicy forArchitecture(SeccompArchitecture architecture) =>
      switch (architecture) {
        SeccompArchitecture.linuxX64 => _linuxX64,
        SeccompArchitecture.linuxArm64 => _linuxArm64,
      };

  final SeccompArchitecture architecture;
  final int auditArchitecture;
  final int seccompSystemCall;
  final int ptraceSystemCall;
  final int socketSystemCall;
  final int socketPairSystemCall;
  final int connectSystemCall;
  final int bindSystemCall;
  final int setsidSystemCall;
  final int setpgidSystemCall;
  final int unshareSystemCall;

  SeccompFilterProgram buildProgram() {
    final assembler = _SeccompAssembler()
      ..loadWord(auditArchitectureOffset)
      ..jumpEqual(
        auditArchitecture,
        whenTrue: 'load-system-call',
        whenFalse: 'kill-architecture',
      )
      ..label('kill-architecture')
      ..returnValue(returnKillProcess)
      ..label('load-system-call')
      ..loadWord(systemCallOffset);

    if (architecture == SeccompArchitecture.linuxX64) {
      assembler
        ..jumpGreaterOrEqual(
          x32SystemCallBit,
          whenTrue: 'kill-x32',
          whenFalse: 'dispatch',
        )
        ..label('kill-x32')
        ..returnValue(returnKillProcess);
    }

    assembler
      ..label('dispatch')
      ..jumpEqual(
        socketSystemCall,
        whenTrue: 'socket-domain',
        whenFalse: 'check-ptrace',
      )
      ..label('check-ptrace')
      ..jumpEqual(
        ptraceSystemCall,
        whenTrue: 'deny',
        whenFalse: 'check-setsid',
      )
      ..label('check-setsid')
      ..jumpEqual(
        setsidSystemCall,
        whenTrue: 'deny',
        whenFalse: 'check-setpgid',
      )
      ..label('check-setpgid')
      ..jumpEqual(
        setpgidSystemCall,
        whenTrue: 'deny',
        whenFalse: 'check-unshare',
      )
      ..label('check-unshare')
      ..jumpEqual(
        unshareSystemCall,
        whenTrue: 'deny',
        whenFalse: 'allow',
      )
      ..label('socket-domain')
      ..loadWord(argument0Offset)
      ..jumpEqual(
        addressFamilyInet,
        whenTrue: 'socket-type',
        whenFalse: 'check-inet6',
      )
      ..label('check-inet6')
      ..jumpEqual(
        addressFamilyInet6,
        whenTrue: 'socket-type',
        whenFalse: 'deny',
      )
      ..label('socket-type')
      ..loadWord(argument1Offset)
      ..andValue(socketTypeMask)
      ..jumpEqual(
        socketStream,
        whenTrue: 'allow',
        whenFalse: 'deny',
      )
      ..label('deny')
      ..returnValue(returnPermissionDenied)
      ..label('allow')
      ..returnValue(returnAllow);

    return SeccompFilterProgram(assembler.finish());
  }
}

final class _SeccompAssembler {
  final List<_PendingInstruction> _instructions = <_PendingInstruction>[];
  final Map<String, int> _labels = <String, int>{};

  void label(String name) {
    if (_labels.containsKey(name)) {
      throw StateError('Duplicate seccomp label $name.');
    }
    _labels[name] = _instructions.length;
  }

  void loadWord(int offset) {
    _instructions.add(
      _PendingInstruction(
          code: SeccompPolicy.bpfLoadWordAbsolute, value: offset),
    );
  }

  void andValue(int value) {
    _instructions.add(
      _PendingInstruction(code: SeccompPolicy.bpfAnd, value: value),
    );
  }

  void jumpEqual(
    int value, {
    required String whenTrue,
    required String whenFalse,
  }) {
    _instructions.add(
      _PendingInstruction(
        code: SeccompPolicy.bpfJumpEqual,
        value: value,
        whenTrue: whenTrue,
        whenFalse: whenFalse,
      ),
    );
  }

  void jumpGreaterOrEqual(
    int value, {
    required String whenTrue,
    required String whenFalse,
  }) {
    _instructions.add(
      _PendingInstruction(
        code: SeccompPolicy.bpfJumpGreaterOrEqual,
        value: value,
        whenTrue: whenTrue,
        whenFalse: whenFalse,
      ),
    );
  }

  void returnValue(int value) {
    _instructions.add(
      _PendingInstruction(code: SeccompPolicy.bpfReturn, value: value),
    );
  }

  List<SeccompFilterInstruction> finish() {
    return List<SeccompFilterInstruction>.unmodifiable(
      <SeccompFilterInstruction>[
        for (var index = 0; index < _instructions.length; index += 1)
          _instructions[index].resolve(index, _labels),
      ],
    );
  }
}

final class _PendingInstruction {
  const _PendingInstruction({
    required this.code,
    required this.value,
    this.whenTrue,
    this.whenFalse,
  });

  final int code;
  final int value;
  final String? whenTrue;
  final String? whenFalse;

  SeccompFilterInstruction resolve(int index, Map<String, int> labels) {
    return SeccompFilterInstruction(
      code: code,
      jumpTrue: _resolveOffset(index, whenTrue, labels),
      jumpFalse: _resolveOffset(index, whenFalse, labels),
      value: value,
    );
  }

  static int _resolveOffset(
    int index,
    String? label,
    Map<String, int> labels,
  ) {
    if (label == null) return 0;
    final target = labels[label];
    if (target == null) throw StateError('Unknown seccomp label $label.');
    final offset = target - index - 1;
    if (offset < 0 || offset > 0xff) {
      throw StateError('Invalid classic BPF jump to $label.');
    }
    return offset;
  }
}
