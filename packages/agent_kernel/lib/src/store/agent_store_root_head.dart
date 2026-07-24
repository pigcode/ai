import 'agent_store_head.dart';
import 'store_head_digest.dart';

final class AgentStoreRootHead {
  const AgentStoreRootHead({
    required this.sequence,
    required this.stateDigest,
    required this.sessionCatalogRootDigest,
    required this.createSessionCommandRegistryRootDigest,
    required this.generation,
  });

  factory AgentStoreRootHead.compose({
    required int sequence,
    required String sessionCatalogRootDigest,
    required String createSessionCommandRegistryRootDigest,
    required int generation,
  }) {
    final stateDigest = composeStoreRootHeadDigest(
      sequence: sequence,
      sessionCatalogRootDigest: sessionCatalogRootDigest,
      createSessionCommandRegistryRootDigest:
          createSessionCommandRegistryRootDigest,
      generation: generation,
    );
    return AgentStoreRootHead(
      sequence: sequence,
      stateDigest: stateDigest,
      sessionCatalogRootDigest: sessionCatalogRootDigest,
      createSessionCommandRegistryRootDigest:
          createSessionCommandRegistryRootDigest,
      generation: generation,
    );
  }

  static final empty = AgentStoreRootHead.compose(
    sequence: 0,
    sessionCatalogRootDigest: agentStoreEmptyDigest,
    createSessionCommandRegistryRootDigest: agentStoreEmptyDigest,
    generation: 0,
  );

  final int sequence;
  final String stateDigest;
  final String sessionCatalogRootDigest;
  final String createSessionCommandRegistryRootDigest;
  final int generation;

  Map<String, Object?> toJson() => <String, Object?>{
        'sequence': sequence,
        'stateDigest': stateDigest,
        'sessionCatalogRootDigest': sessionCatalogRootDigest,
        'createSessionCommandRegistryRootDigest':
            createSessionCommandRegistryRootDigest,
        'generation': generation,
      };

  @override
  bool operator ==(Object other) =>
      other is AgentStoreRootHead &&
      sequence == other.sequence &&
      stateDigest == other.stateDigest &&
      sessionCatalogRootDigest == other.sessionCatalogRootDigest &&
      createSessionCommandRegistryRootDigest ==
          other.createSessionCommandRegistryRootDigest &&
      generation == other.generation;

  @override
  int get hashCode => Object.hash(
        sequence,
        stateDigest,
        sessionCatalogRootDigest,
        createSessionCommandRegistryRootDigest,
        generation,
      );
}
