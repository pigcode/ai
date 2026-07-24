import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

import 'journal_frame_codec.dart';

enum RecoveryDiagnosticCategory {
  partialFinalTailDiscarded,
}

final class RecoveryDiagnostic {
  const RecoveryDiagnostic({
    required this.category,
    required this.segmentIndex,
    required this.offset,
    required this.discardedBytes,
  });

  final RecoveryDiagnosticCategory category;
  final int segmentIndex;
  final int offset;
  final int discardedBytes;
}

final class RecoveryReport {
  RecoveryReport({
    required this.sessionId,
    required List<DecodedJournalSegment> segments,
    required List<RecoveryDiagnostic> diagnostics,
  })  : segments = List<DecodedJournalSegment>.unmodifiable(segments),
        diagnostics = List<RecoveryDiagnostic>.unmodifiable(diagnostics);

  final SessionId sessionId;
  final List<DecodedJournalSegment> segments;
  final List<RecoveryDiagnostic> diagnostics;

  List<AgentEvent> get events => <AgentEvent>[
        for (final segment in segments) ...segment.events,
      ];

  int get nextSequence =>
      events.isEmpty ? segments.first.startSequence : events.last.sequence + 1;

  String get finalRecordDigest => segments.last.finalRecordDigest
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  bool get discardedPartialTail => diagnostics.isNotEmpty;
}
