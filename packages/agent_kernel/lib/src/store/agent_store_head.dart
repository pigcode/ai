import 'store_head_digest.dart';

const agentStoreEmptyDigest =
    '0000000000000000000000000000000000000000000000000000000000000000';

final class AgentStoreHead {
  const AgentStoreHead({
    required this.sequence,
    required this.stateDigest,
    required this.journalHeadDigest,
    required this.identityRegistryRootDigest,
    required this.commandRegistryRootDigest,
    required this.generation,
    required this.historyFloorSequence,
  });

  factory AgentStoreHead.compose({
    required int sequence,
    required String journalHeadDigest,
    required String identityRegistryRootDigest,
    required String commandRegistryRootDigest,
    required int generation,
    required int historyFloorSequence,
  }) {
    final stateDigest = composeStoreHeadDigest(
      sequence: sequence,
      journalHeadDigest: journalHeadDigest,
      identityRegistryRootDigest: identityRegistryRootDigest,
      commandRegistryRootDigest: commandRegistryRootDigest,
      generation: generation,
    );
    return AgentStoreHead(
      sequence: sequence,
      stateDigest: stateDigest,
      journalHeadDigest: journalHeadDigest,
      identityRegistryRootDigest: identityRegistryRootDigest,
      commandRegistryRootDigest: commandRegistryRootDigest,
      generation: generation,
      historyFloorSequence: historyFloorSequence,
    );
  }

  static final empty = AgentStoreHead.compose(
    sequence: 0,
    journalHeadDigest: agentStoreEmptyDigest,
    identityRegistryRootDigest: agentStoreEmptyDigest,
    commandRegistryRootDigest: agentStoreEmptyDigest,
    generation: 0,
    historyFloorSequence: 0,
  );

  final int sequence;
  final String stateDigest;
  final String journalHeadDigest;
  final String identityRegistryRootDigest;
  final String commandRegistryRootDigest;
  final int generation;
  final int historyFloorSequence;

  Map<String, Object?> toJson() => <String, Object?>{
        'sequence': sequence,
        'stateDigest': stateDigest,
        'journalHeadDigest': journalHeadDigest,
        'identityRegistryRootDigest': identityRegistryRootDigest,
        'commandRegistryRootDigest': commandRegistryRootDigest,
        'generation': generation,
        'historyFloorSequence': historyFloorSequence,
      };

  @override
  bool operator ==(Object other) =>
      other is AgentStoreHead &&
      sequence == other.sequence &&
      stateDigest == other.stateDigest &&
      journalHeadDigest == other.journalHeadDigest &&
      identityRegistryRootDigest == other.identityRegistryRootDigest &&
      commandRegistryRootDigest == other.commandRegistryRootDigest &&
      generation == other.generation &&
      historyFloorSequence == other.historyFloorSequence;

  @override
  int get hashCode => Object.hash(
        sequence,
        stateDigest,
        journalHeadDigest,
        identityRegistryRootDigest,
        commandRegistryRootDigest,
        generation,
        historyFloorSequence,
      );
}
