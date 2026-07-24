import 'dart:convert';
import 'dart:typed_data';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  final event0 = EventId.parse('evt_00000000000000000000000000000000');
  final event1 = EventId.parse('evt_00000000000000000000000000000001');
  final command0 = CommandId.parse('cmd_00000000000000000000000000000000');
  final session0 = SessionId.parse('ses_00000000000000000000000000000000');

  test('identity registry is canonical, sorted, typed, and exact', () {
    const codec = IdentityRegistryCodec();
    final artifact = codec.encodeChunk(
      AgentIdentityKind.event,
      <IdentityRegistryEntry>[
        IdentityRegistryEntry(event1),
        IdentityRegistryEntry(event0),
      ],
    );
    final decoded = codec.decodeChunk(
      artifact.bytes,
      expectedKind: AgentIdentityKind.event,
    );

    expect(
      decoded.entries.map((entry) => entry.id),
      <OpaqueId>[event0, event1],
    );
    expect(decoded.reference.digest, artifact.reference.digest);
    expect(
      () => codec.encodeChunk(
        AgentIdentityKind.event,
        <IdentityRegistryEntry>[
          IdentityRegistryEntry(event0),
          IdentityRegistryEntry(event0),
        ],
      ),
      throwsStoreCode(StoreFormatErrorCode.registryViolation),
    );
    expect(
      () => codec.decodeChunk(
        Uint8List.fromList(<int>[...artifact.bytes, 0x0a]),
      ),
      throwsStoreCode(StoreFormatErrorCode.nonCanonicalJson),
    );
  });

  test('session command registry binds content digest and receipt', () {
    const codec = CommandRegistryCodec();
    final command = AgentStoreAcceptedCommand(
      commandId: command0,
      contentDigest: ''.padLeft(64, '1'),
      receipt: <String, Object?>{
        'eventIds': <Object?>[
          event0.value,
        ],
        'sequence': 1,
      },
    );
    final artifact = codec.encodeChunk(<AgentStoreAcceptedCommand>[command]);
    final decoded = codec.decodeChunk(
      artifact.bytes,
      expectedShard: '00',
    );

    expect(decoded.entries.single.commandId, command0);
    expect(decoded.entries.single.contentDigest, ''.padLeft(64, '1'));
    expect(decoded.entries.single.receipt['sequence'], 1);
  });

  test('root registries preserve Session allocation idempotency data', () {
    const catalogCodec = RootSessionCatalogCodec();
    const commandCodec = RootSessionCommandRegistryCodec();
    final catalog = catalogCodec.encodeChunk(<SessionId>[session0]);
    final rootCommand = commandCodec.encodeChunk(
      <RootSessionCommandEntry>[
        RootSessionCommandEntry(
          commandId: command0,
          contentDigest: ''.padLeft(64, '2'),
          sessionId: session0,
          receipt: <String, Object?>{
            'sessionId': session0.value,
            'rootSequence': 1,
          },
        ),
      ],
    );

    expect(
      catalogCodec.decodeChunk(catalog.bytes).entries.single,
      session0,
    );
    final decoded = commandCodec.decodeChunk(rootCommand.bytes).entries.single;
    expect(decoded.commandId, command0);
    expect(decoded.sessionId, session0);
    expect(decoded.contentDigest, ''.padLeft(64, '2'));
  });

  test('manifest binds sorted chunk references, totals, and root digest', () {
    const identityCodec = IdentityRegistryCodec();
    const manifestCodec = RegistryManifestCodec();
    final chunk = identityCodec.encodeChunk(
      AgentIdentityKind.event,
      <IdentityRegistryEntry>[
        IdentityRegistryEntry(event0),
        IdentityRegistryEntry(event1),
      ],
    );
    final bytes = manifestCodec.encode(
      kind: RegistryKind.identity,
      generation: 7,
      chunks: <RegistryChunkReference>[chunk.reference],
    );
    final manifest = manifestCodec.decode(
      bytes,
      expectedKind: RegistryKind.identity,
    );

    expect(manifest.generation, 7);
    expect(manifest.entryCount, 2);
    expect(manifest.totalBytes, chunk.bytes.length);
    manifestCodec.verifyChunks(
      manifest,
      <String, Uint8List>{chunk.reference.digest: chunk.bytes},
    );
    expect(
      () => manifestCodec.verifyChunks(manifest, <String, Uint8List>{}),
      throwsStoreCode(StoreFormatErrorCode.registryViolation),
    );

    final object = jsonDecode(utf8.decode(bytes))! as Map<String, Object?>;
    object['rootDigest'] = ''.padLeft(64, '0');
    expect(
      () => manifestCodec.decode(canonicalJsonBytes(object)),
      throwsStoreCode(StoreFormatErrorCode.digestMismatch),
    );
  });

  test('registry entry and byte limits fail closed', () {
    final countLimited = IdentityRegistryCodec(
      limits: const StoreLimits(maximumRegistryEntries: 1),
    );
    expect(
      () => countLimited.encodeChunk(
        AgentIdentityKind.event,
        <IdentityRegistryEntry>[
          IdentityRegistryEntry(event0),
          IdentityRegistryEntry(event1),
        ],
      ),
      throwsStoreCode(StoreFormatErrorCode.resourceLimit),
    );

    final byteLimited = IdentityRegistryCodec(
      limits: const StoreLimits(maximumRegistryBytes: 32),
    );
    expect(
      () => byteLimited.encodeChunk(
        AgentIdentityKind.event,
        <IdentityRegistryEntry>[IdentityRegistryEntry(event0)],
      ),
      throwsStoreCode(StoreFormatErrorCode.resourceLimit),
    );
  });
}

Matcher throwsStoreCode(StoreFormatErrorCode code) => throwsA(
      isA<StoreFormatException>().having(
        (error) => error.code,
        'code',
        code,
      ),
    );
