import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import '../../exec/process_group.dart';
import 'landlock_ffi.dart';
import 'seccomp_ffi.dart';
import '../runner_control.dart';
import '../sandbox_errors.dart';
import '../sandbox_policy.dart';

Future<void> main(List<String> arguments) async {
  final groupPersisted =
      arguments.isNotEmpty && arguments.first == '--group-persisted';
  final offset = groupPersisted ? 1 : 0;
  if (arguments.length < offset + 4 ||
      arguments[offset] != '--policy' ||
      arguments[offset + 2] != '--') {
    stderr.writeln('invalid sandbox runner invocation');
    exitCode = 64;
    return;
  }
  final policy = _decodePolicy(arguments[offset + 1]);
  final executable = arguments[offset + 3];
  final commandArguments = arguments.sublist(offset + 4);

  final setProcessGroup = DynamicLibrary.process()
      .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
          'setpgid');
  final getProcessGroup = DynamicLibrary.process()
      .lookupFunction<Int32 Function(), int Function()>('getpgrp');
  final getProcessId = DynamicLibrary.process()
      .lookupFunction<Int32 Function(), int Function()>('getpid');
  try {
    if (getProcessGroup() != getProcessId() && setProcessGroup(0, 0) != 0) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'landlock-process-group-create-failed',
      );
    }
    if (!groupPersisted) {
      final processId = getProcessId();
      RunnerControl.report('group-ready', <String, Object?>{
        'identity': ProcessGroup.captureIdentity(processId),
        'pgid': processId,
      });
      RunnerControl.waitForAck('group-ready');
    }
    LandlockFfi().apply(policy);
    SeccompFfi().apply();
    RunnerControl.report('sandbox-ready');
    RunnerControl.waitForAck('sandbox-ready');
    exitCode = await RunnerControl.runTarget(executable, commandArguments);
  } on HostCapabilityException catch (error) {
    RunnerControl.report('error', <String, Object?>{
      'code': error.code.name,
      'rule': error.rule,
    });
    exitCode = 70;
  } on Object {
    RunnerControl.report('error', const <String, Object?>{
      'code': 'sandboxUnavailable',
      'rule': 'landlock-runner-unexpected-failure',
    });
    exitCode = 70;
  }
}

SandboxPolicy _decodePolicy(String encoded) {
  final json = jsonDecode(
    utf8.decode(base64Url.decode(encoded)),
  ) as Map<String, Object?>;
  final roots = (json['roots']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map(
        (root) => SandboxPathRule(
          path: root['path']! as String,
          access: SandboxPathAccess.values.byName(root['access']! as String),
        ),
      )
      .toList();
  final network = (json['networkAllowlist']! as List<Object?>)
      .cast<Map<String, Object?>>()
      .map(
        (endpoint) => SandboxNetworkEndpoint(
          host: endpoint['host']! as String,
          port: endpoint['port']! as int,
        ),
      )
      .toList();
  return SandboxPolicy(
    roots: roots,
    networkAllowlist: network,
    denyReadPaths: (json['denyReadPaths']! as List<Object?>).cast<String>(),
    requiresPty: json['requiresPty']! as bool,
  );
}
