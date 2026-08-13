# Pigcode AI

Pigcode AI is a pure Dart AI SDK with no Flutter dependency. It defines
provider-neutral contracts and provides text and structured object generation
and streaming, embeddings, reranking, image and video generation, speech,
transcription, file and skill uploads, tools, middleware, telemetry, and
provider integrations.

## Packages

| Directory | Package | Purpose |
| --- | --- | --- |
| `packages/provider` | `pigcode_ai_provider` | Provider-neutral contracts for language, embedding, reranking, image, speech, transcription, and video models; messages and stream events; tools and approvals; files and skills; middleware; cancellation; and errors. |
| `packages/provider_utils` | `pigcode_ai_provider_utils` | Shared HTTP, SSE, JSON validation, multipart, response handling, identifiers, media, and streaming tool-call utilities. |
| `packages/ai` | `pigcode_ai` | Core APIs for text and structured object generation and streaming, embeddings, reranking, images, speech, transcription, video, file and skill uploads, tools, middleware, UI message conversion, and telemetry. |
| `packages/openai` | `pigcode_ai_openai` | OpenAI Chat Completions, Responses, embeddings, images, speech, transcription, file and skill uploads, and realtime transcription streaming. |
| `packages/openai_compatible` | `pigcode_ai_openai_compatible` | Configurable OpenAI-compatible Chat Completions and embeddings provider foundation. |
| `packages/anthropic` | `pigcode_ai_anthropic` | Anthropic Messages, tools, file uploads, skill creation, cache control, and an explicit container ID continuation helper. |
| `packages/protocol_utils` | `pigcode_ai_protocol_utils` | Portable JSON-RPC, framing, cancellation, diagnostics, and caller-owned transport primitives. |
| `packages/acp` | `pigcode_ai_acp` | Stable ACP v1 client/agent protocol pinned to `schema-v1.20.0`, with portable core APIs and caller-owned process adapters. |
| `packages/mcp` | `pigcode_ai_mcp` | MCP `2025-11-25` client/server APIs, portable Streamable HTTP, VM-only IO adapters, OAuth, tasks, and Pigcode AI mappings. |
| `packages/agent` | `pigcode_ai_agent` | Portable explicit-Session development Agent facade, Native driver mapping, and Host capability ports. |
| `packages/agent_kernel` | `pigcode_ai_agent_kernel` | Portable event-sourced Agent domain, command, policy, reducer, stream, and Store contracts. |
| `packages/agent_io` | `pigcode_ai_agent_io` | VM-only Agent Store and fail-closed Seatbelt/Landlock Host containment implementation. |
| `packages/agent_dart` | `pigcode_ai_agent_dart` | VM-only Dart tooling composition with sandboxed process launch and proposal-only reverse requests. |
| `packages/lsp` | `pigcode_ai_lsp` | Portable LSP stable APIs, explicit proposed opt-in, lifecycle, capabilities, document state, proposals, and codecs. |
| `packages/dap` | `pigcode_ai_dap` | Portable DAP schema, lifecycle, debug state, proposals, references, and codecs. |
| `packages/dart` | `pigcode_ai_dart` | Portable Analysis Server, DTD, and VM Service protocol APIs with fixed source and runtime profiles. |

## Status

This is a pre-release workspace at version `0.0.1`. All eleven packages declare
`publish_to: none`; publication and stability guarantees will be designed
separately.

## Development

```bash
dart pub get
dart run tool/check_format.dart
dart run tool/check_workspace.dart
dart run tool/protocol_codegen.dart --check
dart run tool/check_protocol_compatibility.dart
dart run tool/check_dart_tooling_compatibility.dart
dart run tool/check_agent_kernel_schema.dart
dart run tool/check_kernel_store_compatibility.dart
dart run tool/check_native_containment_compatibility.dart
dart run melos format
dart run melos analyze
dart run melos test
```

Normal CI and unit tests do not call live model APIs. Live tests are opt-in and
are not part of the normal commands above.

## Compatibility status

Current compatibility claims cover only behavior exercised by this repository's
fixed evidence:

- ACP schema `schema-v1.20.0`, scripted peers, Dart real-process tests, and
  fixed Dart, TypeScript SDK `1.3.0`, and Rust SDK `v2.0.0` peers.
- MCP specification `2025-11-25` and official conformance harness `0.1.16`:
  all 18 applicable client scenarios and all 32 applicable server scenarios.

The pinned source identities and complete scenario inventory live in
[`tool/upstream/protocols/sources.json`](tool/upstream/protocols/sources.json)
and
[`compatibility/upstream/phase-2a-protocol-inventory.json`](compatibility/upstream/phase-2a-protocol-inventory.json).
Claim levels, complete evidence tuples, and known limitations are recorded in
[`compatibility/phase-2a-protocol-foundation.json`](compatibility/phase-2a-protocol-foundation.json)
and summarized in [Protocol support](docs/protocol-support.md).
Install the official MCP harness and reproduce the evidence with:

```bash
npm ci --prefix tool/conformance/mcp --ignore-scripts
dart run tool/run_mcp_conformance.dart --role client --suite all
dart run tool/run_mcp_conformance.dart --role server --suite all
```

Phase 3 adds a portable event-sourced Agent Kernel and a VM-only reference
Store. Its 28 bounded claims, evidence digests, actual platform tuple, and
known unsupported capabilities are recorded in
[`compatibility/phase-3-kernel-store.json`](compatibility/phase-3-kernel-store.json)
and summarized in [Kernel and Store support](docs/kernel-store-support.md).
`processCrashFlush` means a complete artifact was flushed before its receipt;
it is process/SIGKILL evidence, not raw-device power-loss durability.

Phase 4 adds the portable Native Agent facade and VM-only containment. Its 18
bounded claims, 27 threat-model references, ten-point crash matrix, actual
macOS evidence, CI-deferred Linux implementation, and known unsupported scope
are recorded in
[`compatibility/phase-4-native-containment.json`](compatibility/phase-4-native-containment.json)
and summarized in
[Native containment support](docs/native-containment-support.md). Unsupported
production containment fails closed; `unsafe/dev-only` is never production
evidence.

### Phase 4 machine-checked claims

- `P4-HOST-01`: `implemented`
- `P4-HOST-02`: `verified`
- `P4-HOST-03`: `implemented`
- `P4-HOST-04`: `implemented`
- `P4-HOST-05`: `implemented`
- `P4-HOST-06`: `implemented`
- `P4-HOST-07`: `verified`
- `P4-HOST-08`: `implemented`
- `P4-HOST-09`: `verified`
- `P4-HOST-10`: `implemented`
- `P4-AGENT-01`: `implemented`
- `P4-AGENT-02`: `implemented`
- `P4-AGENT-03`: `implemented`
- `P4-DART-01`: `verified`
- `P4-DART-02`: `known-unsupported`
- `P4-CROSS-01`: `implemented`
- `P4-CROSS-02`: `implemented`
- `P4-CROSS-03`: `implemented`

Phase 2b adds 41 bounded Dart tooling claims across LSP, DAP, Analysis Server,
DTD, VM Service, and cross-package portability. Exact source revisions, peer
profiles, evidence, and unsupported scope are recorded in
[`compatibility/phase-2b-dart-tooling.json`](compatibility/phase-2b-dart-tooling.json)
and summarized in [Dart tooling protocol support](docs/dart-tooling-support.md).
The libraries remain transport-independent and do not grant host authorization
or perform process, terminal, socket, or filesystem side effects.

## License and provenance

Pigcode AI is licensed under the [MIT License](LICENSE). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party provenance and
the [Apache License 2.0](third_party/licenses/Apache-2.0.txt) for the
corresponding attribution text.
