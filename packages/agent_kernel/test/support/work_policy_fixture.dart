import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';

WorkItemRequest workRequest(
  RunId runId, {
  EffectControl effectControl = EffectControl.managed,
  String principal = 'principal:test',
  String toolIdentity = 'tool:test',
  Map<String, Object?> arguments = const <String, Object?>{'value': 1},
  String workspaceScopeReference = 'workspace:test',
  String environmentAllowlistDigest =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String capabilityGrantVersion = 'grant/v1',
  DateTime? approvalExpiresAt,
}) =>
    WorkItemRequest(
      runId: runId,
      principal: principal,
      toolIdentity: toolIdentity,
      arguments: arguments,
      workspaceScopeReference: workspaceScopeReference,
      environmentAllowlistDigest: environmentAllowlistDigest,
      capabilityGrantVersion: capabilityGrantVersion,
      effectControl: effectControl,
      approvalExpiresAt: approvalExpiresAt ?? DateTime.utc(2026, 7, 25),
    );

ExplicitGrantPolicy workPolicy({
  required EffectControl effectControl,
  bool requireApproval = false,
  String version = 'policy/v1',
}) =>
    ExplicitGrantPolicy(
      version: version,
      grants: <ExplicitPolicyGrant>[
        ExplicitPolicyGrant(
          principal: 'principal:test',
          toolIdentity: 'tool:test',
          workspaceScopeReference: 'workspace:test',
          environmentAllowlistDigest:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          capabilityGrantVersion: 'grant/v1',
          effectControls: <EffectControl>{effectControl},
          requireApproval: requireApproval,
        ),
      ],
    );

ApprovalBinding approvalBinding(
  WorkItemRequest request,
  WorkItemId workItemId,
  String policyVersion,
) =>
    ApprovalBinding(
      principal: request.principal,
      workItemId: workItemId,
      toolIdentity: request.toolIdentity,
      arguments: request.arguments,
      workspaceScopeReference: request.workspaceScopeReference,
      environmentAllowlistDigest: request.environmentAllowlistDigest,
      capabilityGrantVersion: request.capabilityGrantVersion,
      policyVersion: policyVersion,
      expiresAt: request.approvalExpiresAt,
    );

final proposeWorkCommandId =
    CommandId.parse('cmd_70000000000000000000000000000000');
final resolveApprovalCommandId =
    CommandId.parse('cmd_71000000000000000000000000000000');
final startWorkCommandId =
    CommandId.parse('cmd_72000000000000000000000000000000');
final outcomeWorkCommandId =
    CommandId.parse('cmd_73000000000000000000000000000000');
