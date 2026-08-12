import 'dart:convert';
import 'dart:io';

import '../runner_control.dart';
import '../sandbox_errors.dart';

Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 1) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'seatbelt-ready-runner-invalid-invocation',
      );
    }
    final command = jsonDecode(utf8.decode(base64Url.decode(arguments.single)))
        as Map<String, Object?>;
    RunnerControl.report('sandbox-ready');
    RunnerControl.waitForAck('sandbox-ready');
    exitCode = await RunnerControl.runTarget(
      command['executable']! as String,
      (command['arguments']! as List<Object?>).cast<String>(),
    );
  } on HostCapabilityException catch (error) {
    RunnerControl.report('error', <String, Object?>{
      'code': error.code.name,
      'rule': error.rule,
    });
    exitCode = 70;
  } on Object {
    RunnerControl.report('error', const <String, Object?>{
      'code': 'sandboxUnavailable',
      'rule': 'seatbelt-ready-runner-unexpected-failure',
    });
    exitCode = 70;
  }
}
