import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../sandbox/sandbox_errors.dart';
import 'process_cleanup_ledger.dart';
import 'process_group.dart';

enum ProcessRecoveryStatus {
  cleaned,
  alreadyExited,
  identityMismatch,
  cleanupUnconfirmed,
}

final class ProcessRecoveryResult {
  const ProcessRecoveryResult({
    required this.record,
    required this.status,
  });

  final ProcessCleanupRecord record;
  final ProcessRecoveryStatus status;

  bool get confirmed =>
      status == ProcessRecoveryStatus.cleaned ||
      status == ProcessRecoveryStatus.alreadyExited;
}

final class ProcessRecoveryReport {
  const ProcessRecoveryReport(this.results);

  final List<ProcessRecoveryResult> results;

  bool get confirmed => results.every((result) => result.confirmed);
}

final class ProcessRecoveryCoordinator {
  ProcessRecoveryCoordinator(String hostDataDirectory)
      : hostDataDirectory = hostDataDirectory {
    if (!hostDataDirectory.startsWith('/')) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'host-data-directory-must-be-absolute',
      );
    }
  }

  final String hostDataDirectory;

  Directory get ledgerDirectory =>
      Directory('$hostDataDirectory/process-cleanup');

  String ledgerPathFor(String sessionIdentity) {
    if (sessionIdentity.isEmpty || sessionIdentity.contains('\u0000')) {
      throw const HostCapabilityException(
        HostCapabilityError.processCleanupFailed,
        'stable-session-identity-invalid',
      );
    }
    final digest = sha256.convert(utf8.encode(sessionIdentity)).toString();
    return '${ledgerDirectory.path}/$digest.cleanup.json';
  }

  Future<ProcessRecoveryReport> recoverPending() async {
    if (!await ledgerDirectory.exists()) {
      return const ProcessRecoveryReport(<ProcessRecoveryResult>[]);
    }
    final files = await ledgerDirectory
        .list(followLinks: false)
        .where(
          (entry) => entry is File && entry.path.endsWith('.cleanup.json'),
        )
        .cast<File>()
        .toList();
    files.sort((left, right) => left.path.compareTo(right.path));
    final results = <ProcessRecoveryResult>[];
    for (final file in files) {
      final ledger = ProcessCleanupLedger(file.path);
      for (final record in await ledger.all()) {
        final current = ProcessGroup.captureIdentity(record.processGroupId);
        if (current == null) {
          await ledger.confirm(record);
          results.add(
            ProcessRecoveryResult(
              record: record,
              status: ProcessRecoveryStatus.alreadyExited,
            ),
          );
          continue;
        }
        if (current != record.processIdentity) {
          results.add(
            ProcessRecoveryResult(
              record: record,
              status: ProcessRecoveryStatus.identityMismatch,
            ),
          );
          continue;
        }
        final cleanup = await ProcessGroup(record.processGroupId).cleanup();
        if (cleanup.confirmed) {
          await ledger.confirm(record);
        }
        results.add(
          ProcessRecoveryResult(
            record: record,
            status: cleanup.confirmed
                ? ProcessRecoveryStatus.cleaned
                : ProcessRecoveryStatus.cleanupUnconfirmed,
          ),
        );
      }
    }
    return ProcessRecoveryReport(
        List<ProcessRecoveryResult>.unmodifiable(results));
  }
}
