import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'sandbox_errors.dart';
import 'sandbox_startup_handshake.dart';

abstract final class RunnerControl {
  static Future<void> report(
    String type, [
    Map<String, Object?> fields = const {},
  ]) async {
    stdout.writeln(
      '$sandboxControlPrefix${jsonEncode(<String, Object?>{
            'type': type,
            ...fields,
          })}',
    );
    await stdout.flush();
  }

  static void waitForAck(String phase) {
    final read = DynamicLibrary.process().lookupFunction<
        IntPtr Function(Int32, Pointer<Uint8>, IntPtr),
        int Function(int, Pointer<Uint8>, int)>('read');
    final byte = _calloc(1).cast<Uint8>();
    final bytes = <int>[];
    try {
      while (bytes.length <= 128) {
        final count = read(0, byte, 1);
        if (count != 1) {
          throw const HostCapabilityException(
            HostCapabilityError.sandboxUnavailable,
            'sandbox-control-channel-closed',
          );
        }
        if (byte.value == 0x0a) break;
        bytes.add(byte.value);
      }
    } finally {
      _free(byte);
    }
    if (utf8.decode(bytes) != '$sandboxAckPrefix$phase') {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'sandbox-control-ack-invalid',
      );
    }
  }

  static Future<int> runTarget(
    String executable,
    List<String> arguments,
  ) async {
    try {
      final process = await Process.start(
        executable,
        arguments,
        runInShell: false,
      );
      await report('exec-ready', <String, Object?>{'pid': process.pid});
      final output = process.stdout.pipe(stdout);
      final errors = process.stderr.pipe(stderr);
      unawaited(stdin.pipe(process.stdin).catchError((_) {}));
      final result = await process.exitCode;
      await Future.wait<void>(<Future<void>>[output, errors]);
      return result;
    } on ProcessException {
      await report('error', const <String, Object?>{
        'code': 'sandboxUnavailable',
        'rule': 'sandbox-target-exec-failed',
      });
      return 70;
    }
  }

  static Pointer<Void> _calloc(int bytes) {
    final calloc = DynamicLibrary.process().lookupFunction<
        Pointer<Void> Function(Uint64, Uint64),
        Pointer<Void> Function(int, int)>('calloc');
    final pointer = calloc(1, bytes);
    if (pointer == nullptr) {
      throw const HostCapabilityException(
        HostCapabilityError.sandboxUnavailable,
        'native-allocation-failed',
      );
    }
    return pointer;
  }

  static void _free(Pointer<NativeType> pointer) {
    final free = DynamicLibrary.process().lookupFunction<
        Void Function(Pointer<Void>), void Function(Pointer<Void>)>('free');
    free(pointer.cast<Void>());
  }
}
