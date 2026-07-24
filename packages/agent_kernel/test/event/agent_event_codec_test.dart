import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  group('AgentEvent codec', () {
    test('round-trips one event from every family', () {
      final events = <AgentEvent>[
        _event(AgentEventType.sessionCreated),
        _event(AgentEventType.runCreated, runId: _runId),
        _event(AgentEventType.runCompleted, runId: _runId),
        _event(
          AgentEventType.workProposed,
          runId: _runId,
          workItemId: _workItemId,
        ),
        _event(
          AgentEventType.deferredCreated,
          runId: _runId,
          payload: <String, Object?>{
            'deferredOperationId': _deferredOperationId.value,
          },
        ),
        _event(
          AgentEventType.resourceRegistered,
          payload: <String, Object?>{
            'runtimeResourceId': _runtimeResourceId.value,
          },
        ),
        _event(AgentEventType.driverProposalRejected),
      ];

      for (final event in events) {
        final encoded = AgentEventCodec.instance.encode(event);
        final decoded = AgentEventCodec.instance.decode(encoded);
        expect(
          AgentEventCodec.instance.encode(decoded),
          encoded,
          reason: event.type.wireName,
        );
      }
    });

    test('rejects wrong schema, sequence, wall time, and causation kind', () {
      expect(
        () => _event(AgentEventType.sessionCreated, schemaVersion: 2),
        throwsA(_codecCode('unsupported_event_schema')),
      );
      expect(
        () => _event(AgentEventType.sessionCreated, sequence: 0),
        throwsA(_codecCode('invalid_event_sequence')),
      );
      expect(
        () => AgentEvent(
          eventId: _eventId,
          schemaVersion: 1,
          sessionId: _sessionId,
          sequence: 1,
          recordedAt: DateTime(2026, 7, 24),
          type: AgentEventType.sessionCreated,
          causationId: _commandId,
          payload: const <String, Object?>{},
          metadata: AgentEventMetadata.empty(),
        ),
        throwsA(_codecCode('invalid_recorded_at')),
      );
      expect(
        () => AgentEvent(
          eventId: _eventId,
          schemaVersion: 1,
          sessionId: _sessionId,
          sequence: 1,
          recordedAt: _recordedAt,
          type: AgentEventType.sessionCreated,
          causationId: _sessionId,
          payload: const <String, Object?>{},
          metadata: AgentEventMetadata.empty(),
        ),
        throwsA(_codecCode('invalid_causation_id')),
      );
    });

    test('enforces required envelope and payload ID kinds', () {
      expect(
        () => _event(AgentEventType.runCreated),
        throwsA(_codecCode('missing_context_id')),
      );
      expect(
        () => _event(AgentEventType.runAttemptStarted, runId: _runId),
        throwsA(_codecCode('missing_context_id')),
      );
      expect(
        () => _event(
          AgentEventType.workProposed,
          runId: _runId,
          workItemId: _workItemId,
          payload: const <String, Object?>{},
        ),
        returnsNormally,
      );
      expect(
        () => AgentEventCodec.instance.decodeObject(<String, Object?>{
          ..._event(
            AgentEventType.workProposed,
            runId: _runId,
            workItemId: _workItemId,
          ).toJson(),
          'workItemId': _eventId.value,
        }),
        throwsA(_codecCode('invalid_context_id')),
      );
      expect(
        () => _event(
          AgentEventType.resourceRegistered,
          payload: const <String, Object?>{},
        ),
        throwsA(_codecCode('missing_context_id')),
      );
    });

    test('payload and metadata are detached immutable JSON', () {
      final mutable = <String, Object?>{
        'nested': <Object?>['before'],
      };
      final event = _event(
        AgentEventType.sessionCreated,
        payload: mutable,
      );
      (mutable['nested']! as List<Object?>)[0] = 'after';

      expect(event.payload['nested'], <Object?>['before']);
      expect(
        () => (event.payload['nested']! as List<Object?>).add('mutation'),
        throwsUnsupportedError,
      );
      expect(() => event.payload['new'] = true, throwsUnsupportedError);
    });
  });

  group('AgentEvent metadata and errors', () {
    test('accepts only registered metadata namespaces', () {
      final metadata = AgentEventMetadata.fromJson(
        const <String, Object?>{
          'pigcode.audit': <String, Object?>{'source': 'test'},
        },
      );
      expect(metadata.toJson()['pigcode.audit'], isNotNull);

      expect(
        () => AgentEventMetadata.fromJson(
          const <String, Object?>{
            'unknown.privileged': <String, Object?>{},
          },
        ),
        throwsA(_codecCode('unknown_metadata_namespace')),
      );
    });

    test('rejects credential keys and values from metadata', () {
      final marker = <String>['sk', '-', 'abcdefghijklmnopqrstuvwx'].join();
      expect(
        () => AgentEventMetadata.fromJson(<String, Object?>{
          'pigcode.audit': <String, Object?>{'authorization': 'redacted'},
        }),
        throwsA(_codecCode('metadata_secret_rejected')),
      );
      expect(
        () => AgentEventMetadata.fromJson(<String, Object?>{
          'pigcode.audit': <String, Object?>{'note': marker},
        }),
        throwsA(_codecCode('metadata_secret_rejected')),
      );
    });

    test('serializes stable AgentError and AgentCommandError fields', () {
      final error = AgentCommandError(
        code: AgentErrorCode.preconditionFailed,
        scope: AgentErrorScope.session,
        phase: AgentErrorPhase.acceptance,
        source: AgentErrorSource.kernel,
        retryDisposition: AgentRetryDisposition.afterRefresh,
        effect: AgentEffect.none,
        safeMessage: 'The session handle is stale.',
        namespacedDetails: AgentEventMetadata.fromJson(
          const <String, Object?>{
            'pigcode.audit': <String, Object?>{'reason': 'headMismatch'},
          },
        ),
      );

      expect(error.toJson(), <String, Object?>{
        'code': 'preconditionFailed',
        'scope': 'session',
        'phase': 'acceptance',
        'source': 'kernel',
        'retryDisposition': 'afterRefresh',
        'effect': 'none',
        'safeMessage': 'The session handle is stale.',
        'namespacedDetails': <String, Object?>{
          'pigcode.audit': <String, Object?>{'reason': 'headMismatch'},
        },
      });
    });
  });
}

AgentEvent _event(
  AgentEventType type, {
  int schemaVersion = 1,
  int sequence = 1,
  RunId? runId,
  AttemptId? attemptId,
  WorkItemId? workItemId,
  Map<String, Object?> payload = const <String, Object?>{},
}) =>
    AgentEvent(
      eventId: _eventId,
      schemaVersion: schemaVersion,
      sessionId: _sessionId,
      sequence: sequence,
      recordedAt: _recordedAt,
      type: type,
      runId: runId,
      attemptId: attemptId,
      workItemId: workItemId,
      causationId: _commandId,
      payload: payload,
      metadata: AgentEventMetadata.empty(),
    );

Matcher _codecCode(String code) => isA<AgentEventCodecException>().having(
      (error) => error.code,
      'code',
      code,
    );

final _eventId = EventId.parse('evt_00000000000000000000000000000000');
final _sessionId = SessionId.parse('ses_00000000000000000000000000000000');
final _runId = RunId.parse('run_00000000000000000000000000000000');
final _commandId = CommandId.parse('cmd_00000000000000000000000000000000');
final _workItemId = WorkItemId.parse('wrk_00000000000000000000000000000000');
final _deferredOperationId =
    DeferredOperationId.parse('dop_00000000000000000000000000000000');
final _runtimeResourceId =
    RuntimeResourceId.parse('res_00000000000000000000000000000000');
final _recordedAt = DateTime.utc(2026, 7, 24);
