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

## Status

This is a pre-release workspace at version `0.0.1`. All nine packages declare
`publish_to: none`; publication and stability guarantees will be designed
separately.

## Development

```bash
dart pub get
dart run tool/check_workspace.dart
dart run tool/protocol_codegen.dart --check
dart run tool/check_protocol_compatibility.dart
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

## License and provenance

Pigcode AI is licensed under the [MIT License](LICENSE). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party provenance and
the [Apache License 2.0](third_party/licenses/Apache-2.0.txt) for the
corresponding attribution text.
