import 'package:pigcode_ai_agent_io/src/sandbox/landlock/seccomp_policy.dart';
import 'package:test/test.dart';

void main() {
  const architectures = <SeccompArchitecture>[
    SeccompArchitecture.linuxX64,
    SeccompArchitecture.linuxArm64,
  ];

  test('seccomp_data offsets match the x86_64 and arm64 Linux UAPI', () {
    expect(SeccompPolicy.systemCallOffset, 0);
    expect(SeccompPolicy.auditArchitectureOffset, 4);
    expect(SeccompPolicy.argument0Offset, 16);
    expect(SeccompPolicy.argument1Offset, 24);

    final x64 = SeccompPolicy.forArchitecture(SeccompArchitecture.linuxX64);
    expect(x64.auditArchitecture, 0xc000003e);
    expect(x64.seccompSystemCall, 317);
    expect(x64.socketSystemCall, 41);
    expect(x64.socketPairSystemCall, 53);
    expect(x64.connectSystemCall, 42);
    expect(x64.bindSystemCall, 49);
    expect(x64.ptraceSystemCall, 101);
    expect(x64.setsidSystemCall, 112);
    expect(x64.setpgidSystemCall, 109);
    expect(x64.unshareSystemCall, 272);

    final arm64 = SeccompPolicy.forArchitecture(SeccompArchitecture.linuxArm64);
    expect(arm64.auditArchitecture, 0xc00000b7);
    expect(arm64.seccompSystemCall, 277);
    expect(arm64.socketSystemCall, 198);
    expect(arm64.socketPairSystemCall, 199);
    expect(arm64.connectSystemCall, 203);
    expect(arm64.bindSystemCall, 200);
    expect(arm64.ptraceSystemCall, 117);
    expect(arm64.setsidSystemCall, 157);
    expect(arm64.setpgidSystemCall, 154);
    expect(arm64.unshareSystemCall, 97);
  });

  for (final architecture in architectures) {
    group(architecture.name, () {
      final policy = SeccompPolicy.forArchitecture(architecture);
      final program = policy.buildProgram();

      test('allows only IPv4 and IPv6 stream socket creation', () {
        for (final domain in const <int>[
          SeccompPolicy.addressFamilyInet,
          SeccompPolicy.addressFamilyInet6,
        ]) {
          expect(
            _evaluate(
              policy,
              program,
              policy.socketSystemCall,
              <int>[domain, SeccompPolicy.socketStream],
            ),
            SeccompFilterAction.allow,
          );
          expect(
            _evaluate(
              policy,
              program,
              policy.socketSystemCall,
              <int>[
                domain,
                SeccompPolicy.socketStream |
                    SeccompPolicy.socketNonblock |
                    SeccompPolicy.socketCloexec,
              ],
            ),
            SeccompFilterAction.allow,
          );
        }
      });

      test('denies datagram raw Unix and packet sockets', () {
        for (final arguments in const <List<int>>[
          <int>[
            SeccompPolicy.addressFamilyInet,
            SeccompPolicy.socketDatagram,
          ],
          <int>[SeccompPolicy.addressFamilyInet, SeccompPolicy.socketRaw],
          <int>[
            SeccompPolicy.addressFamilyUnix,
            SeccompPolicy.socketStream,
          ],
          <int>[
            SeccompPolicy.addressFamilyPacket,
            SeccompPolicy.socketRaw,
          ],
        ]) {
          expect(
            _evaluate(
              policy,
              program,
              policy.socketSystemCall,
              arguments,
            ),
            SeccompFilterAction.permissionDenied,
            reason: 'socket arguments $arguments',
          );
        }
      });

      test('allows socketpair only as local runtime IPC', () {
        expect(
          _evaluate(
            policy,
            program,
            policy.socketPairSystemCall,
            const <int>[
              SeccompPolicy.addressFamilyUnix,
              SeccompPolicy.socketStream | SeccompPolicy.socketCloexec,
            ],
          ),
          SeccompFilterAction.allow,
        );
        expect(
          _evaluate(
            policy,
            program,
            policy.socketSystemCall,
            const <int>[
              SeccompPolicy.addressFamilyUnix,
              SeccompPolicy.socketStream | SeccompPolicy.socketCloexec,
            ],
          ),
          SeccompFilterAction.permissionDenied,
        );
      });

      test('keeps ptrace and session escape syscalls denied', () {
        for (final systemCall in <int>[
          policy.ptraceSystemCall,
          policy.setsidSystemCall,
          policy.setpgidSystemCall,
          policy.unshareSystemCall,
        ]) {
          expect(
            _evaluate(policy, program, systemCall),
            SeccompFilterAction.permissionDenied,
            reason: 'system call $systemCall',
          );
        }
      });

      test('delegates TCP connect and bind decisions to Landlock', () {
        expect(
          _evaluate(policy, program, policy.connectSystemCall),
          SeccompFilterAction.allow,
        );
        expect(
          _evaluate(policy, program, policy.bindSystemCall),
          SeccompFilterAction.allow,
        );
      });

      test('kills an AUDIT_ARCH mismatch', () {
        expect(
          program.evaluate(
            auditArchitecture: policy.auditArchitecture ^ 1,
            systemCall: policy.socketPairSystemCall,
          ),
          SeccompFilterAction.killProcess,
        );
      });

      test('all label fixups stay inside the classic BPF program', () {
        for (var index = 0; index < program.instructions.length; index += 1) {
          final instruction = program.instructions[index];
          if (instruction.code != SeccompPolicy.bpfJumpEqual &&
              instruction.code != SeccompPolicy.bpfJumpGreaterOrEqual) {
            continue;
          }
          expect(index + 1 + instruction.jumpTrue,
              lessThan(program.instructions.length));
          expect(index + 1 + instruction.jumpFalse,
              lessThan(program.instructions.length));
        }
      });
    });
  }

  test('x86_64 filter kills the alternate x32 syscall convention', () {
    final policy = SeccompPolicy.forArchitecture(SeccompArchitecture.linuxX64);
    expect(
      _evaluate(
        policy,
        policy.buildProgram(),
        SeccompPolicy.x32SystemCallBit | policy.socketSystemCall,
      ),
      SeccompFilterAction.killProcess,
    );
  });
}

SeccompFilterAction _evaluate(
  SeccompPolicy policy,
  SeccompFilterProgram program,
  int systemCall, [
  List<int> arguments = const <int>[],
]) =>
    program.evaluate(
      auditArchitecture: policy.auditArchitecture,
      systemCall: systemCall,
      arguments: arguments,
    );
