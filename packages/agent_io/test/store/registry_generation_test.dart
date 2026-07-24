import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  const identityCodec = IdentityRegistryCodec();
  const manifestCodec = RegistryManifestCodec();
  final firstId = EventId.parse('evt_00000000000000000000000000000000');
  final secondId = EventId.parse('evt_00000000000000000000000000000001');

  test('same exact registry set has stable root across generations', () {
    final chunk = identityCodec.encodeChunk(
      AgentIdentityKind.event,
      <IdentityRegistryEntry>[IdentityRegistryEntry(firstId)],
    );
    final first = manifestCodec.decode(manifestCodec.encode(
      kind: RegistryKind.identity,
      generation: 1,
      chunks: <RegistryChunkReference>[chunk.reference],
    ));
    final second = manifestCodec.decode(manifestCodec.encode(
      kind: RegistryKind.identity,
      generation: 2,
      chunks: <RegistryChunkReference>[chunk.reference],
    ));

    expect(first.rootDigest, second.rootDigest);
    expect(first.generation, isNot(second.generation));
  });

  test('registry root changes when the exact set changes', () {
    final firstChunk = identityCodec.encodeChunk(
      AgentIdentityKind.event,
      <IdentityRegistryEntry>[IdentityRegistryEntry(firstId)],
    );
    final secondChunk = identityCodec.encodeChunk(
      AgentIdentityKind.event,
      <IdentityRegistryEntry>[
        IdentityRegistryEntry(firstId),
        IdentityRegistryEntry(secondId),
      ],
    );
    final first = manifestCodec.decode(manifestCodec.encode(
      kind: RegistryKind.identity,
      generation: 1,
      chunks: <RegistryChunkReference>[firstChunk.reference],
    ));
    final second = manifestCodec.decode(manifestCodec.encode(
      kind: RegistryKind.identity,
      generation: 2,
      chunks: <RegistryChunkReference>[secondChunk.reference],
    ));

    expect(first.rootDigest, isNot(second.rootDigest));
    expect(second.entryCount, 2);
  });
}
