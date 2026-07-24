import '../event/agent_error.dart';
import '../event/agent_event_metadata.dart';
import '../store/agent_store_transaction.dart';
import 'agent_command_receipt.dart';

AgentCommandReceipt restoreCommandReceipt(
  AgentStoreAcceptedCommand record,
  String expectedContentDigest,
) {
  if (record.contentDigest != expectedContentDigest) {
    throw AgentCommandError(
      code: AgentErrorCode.contentModified,
      scope: AgentErrorScope.command,
      phase: AgentErrorPhase.validation,
      source: AgentErrorSource.kernel,
      retryDisposition: AgentRetryDisposition.never,
      effect: AgentEffect.none,
      safeMessage: 'CommandId was already used with different content.',
      namespacedDetails: AgentEventMetadata.empty(),
    );
  }
  return AgentCommandReceipt.fromJson(record.receipt);
}
