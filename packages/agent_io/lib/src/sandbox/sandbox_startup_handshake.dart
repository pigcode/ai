import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../exec/process_cleanup_ledger.dart';
import '../exec/process_group.dart';
import 'sandbox_errors.dart';
import 'sandbox_prepared_backend.dart';

const sandboxControlPrefix = 'PIGCODE_CONTROL ';
const sandboxAckPrefix = 'PIGCODE_ACK ';

enum SandboxStartupPhase {
  sandboxSetupPreparedBeforeApply,
  processGroupPersistedBeforeAck,
  sandboxAppliedBeforeExecAck,
  targetExecConfirmed,
}

typedef SandboxStartupObserver = Future<void> Function(
  SandboxStartupPhase phase,
  Map<String, Object?> evidence,
);

Future<Stream<List<int>>> awaitSandboxStartup(
  Process process, {
  required PersistProcessGroup persistProcessGroup,
  SandboxStartupObserver? observer,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final output = StreamController<List<int>>();
  final ready = Completer<void>();
  final stdoutClosed = Completer<void>();
  final lineBytes = <int>[];
  var groupReady = false;
  var sandboxReady = false;
  var execReady = false;
  late StreamSubscription<List<int>> subscription;

  Future<void> fail(HostCapabilityException error) async {
    if (ready.isCompleted) return;
    ready.completeError(error);
    process.kill(ProcessSignal.sigkill);
  }

  Future<void> consumeLine(String line) async {
    if (!line.startsWith(sandboxControlPrefix)) {
      await fail(
        const HostCapabilityException(
          HostCapabilityError.sandboxUnavailable,
          'sandbox-handshake-protocol-error',
        ),
      );
      return;
    }
    final message = jsonDecode(line.substring(sandboxControlPrefix.length))
        as Map<String, Object?>;
    switch (message['type']) {
      case 'group-ready':
        final processGroupId = message['pgid'];
        final reportedIdentity = message['identity'];
        final currentIdentity = processGroupId is int
            ? ProcessGroup.captureIdentity(processGroupId)
            : null;
        if (groupReady ||
            processGroupId is! int ||
            reportedIdentity is! String ||
            currentIdentity != reportedIdentity) {
          await fail(
            const HostCapabilityException(
              HostCapabilityError.processCleanupFailed,
              'sandbox-group-handshake-invalid',
            ),
          );
          return;
        }
        await persistProcessGroup(processGroupId);
        await observer?.call(
          SandboxStartupPhase.processGroupPersistedBeforeAck,
          Map<String, Object?>.unmodifiable(message),
        );
        groupReady = true;
        process.stdin.writeln('${sandboxAckPrefix}group-ready');
        await process.stdin.flush();
      case 'sandbox-ready':
        if (!groupReady || sandboxReady) {
          await fail(
            const HostCapabilityException(
              HostCapabilityError.sandboxUnavailable,
              'sandbox-ready-handshake-invalid',
            ),
          );
          return;
        }
        sandboxReady = true;
        await observer?.call(
          SandboxStartupPhase.sandboxAppliedBeforeExecAck,
          Map<String, Object?>.unmodifiable(message),
        );
        process.stdin.writeln('${sandboxAckPrefix}sandbox-ready');
        await process.stdin.flush();
      case 'exec-ready':
        if (!sandboxReady || execReady || message['pid'] is! int) {
          await fail(
            const HostCapabilityException(
              HostCapabilityError.sandboxUnavailable,
              'sandbox-exec-handshake-invalid',
            ),
          );
          return;
        }
        execReady = true;
        await observer?.call(
          SandboxStartupPhase.targetExecConfirmed,
          Map<String, Object?>.unmodifiable(message),
        );
        ready.complete();
      case 'error':
        final codeName = message['code'] as String? ?? 'sandboxUnavailable';
        final code = HostCapabilityError.values
            .where((value) => value.name == codeName)
            .firstOrNull;
        await fail(
          HostCapabilityException(
            code ?? HostCapabilityError.sandboxUnavailable,
            message['rule'] as String? ?? 'sandbox-startup-failed',
          ),
        );
      default:
        await fail(
          const HostCapabilityException(
            HostCapabilityError.sandboxUnavailable,
            'sandbox-handshake-message-unknown',
          ),
        );
    }
  }

  subscription = process.stdout.listen(
    (chunk) async {
      if (execReady) {
        output.add(chunk);
        return;
      }
      subscription.pause();
      try {
        for (var index = 0; index < chunk.length; index += 1) {
          final byte = chunk[index];
          if (byte == 0x0a) {
            final line = utf8.decode(lineBytes);
            lineBytes.clear();
            await consumeLine(line);
            if (execReady && index + 1 < chunk.length) {
              output.add(chunk.sublist(index + 1));
              break;
            }
          } else {
            lineBytes.add(byte);
            if (lineBytes.length > 4096) {
              await fail(
                const HostCapabilityException(
                  HostCapabilityError.sandboxUnavailable,
                  'sandbox-handshake-frame-too-large',
                ),
              );
              break;
            }
          }
        }
      } on HostCapabilityException catch (error) {
        await fail(error);
      } on Object {
        await fail(
          const HostCapabilityException(
            HostCapabilityError.sandboxUnavailable,
            'sandbox-handshake-decode-failed',
          ),
        );
      } finally {
        subscription.resume();
      }
    },
    onError: output.addError,
    onDone: () async {
      await output.close();
      if (!stdoutClosed.isCompleted) stdoutClosed.complete();
    },
  );
  unawaited(
    process.exitCode.then((_) async {
      if (!ready.isCompleted) {
        await stdoutClosed.future.timeout(
          const Duration(milliseconds: 250),
          onTimeout: () {},
        );
      }
      if (!ready.isCompleted) {
        final startupError = await process.stderr.transform(utf8.decoder).join();
        if (startupError.isNotEmpty) stderr.writeln(startupError);
        ready.completeError(
          HostCapabilityException(
            HostCapabilityError.sandboxUnavailable,
            !groupReady
                ? 'sandbox-exited-before-group-ready'
                : !sandboxReady
                    ? 'sandbox-exited-before-sandbox-ready'
                    : 'sandbox-exited-before-exec-ready',
          ),
        );
      }
    }),
  );

  try {
    await ready.future.timeout(timeout);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    final startupError = await process.stderr.transform(utf8.decoder).join();
    if (startupError.isNotEmpty) stderr.writeln(startupError);
    throw const HostCapabilityException(
      HostCapabilityError.sandboxUnavailable,
      'sandbox-handshake-timeout',
    );
  }
  return output.stream;
}

Future<ProcessCleanupRecord> persistStandaloneProcessGroup(
  int processGroupId,
) async {
  throw const HostCapabilityException(
    HostCapabilityError.processCleanupFailed,
    'standalone-sandbox-launch-requires-ledger',
  );
}
