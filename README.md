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

## Status

This is a pre-release workspace at version `0.0.1`. All six packages declare
`publish_to: none`; publication and stability guarantees will be designed
separately.

## Development

```bash
dart pub get
dart run tool/check_workspace.dart
dart run melos format
dart run melos analyze
dart run melos test
```

Normal CI and unit tests do not call live model APIs. Live tests are opt-in and
are not part of the normal commands above.

## Compatibility status

Current compatibility claims cover only behavior exercised by this repository's
tests. Vercel-compatible or other protocol support requires versioned
compatibility evidence; package names alone are not compatibility claims.

## License and provenance

Pigcode AI is licensed under the [MIT License](LICENSE). See
[THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for third-party provenance and
the [Apache License 2.0](third_party/licenses/Apache-2.0.txt) for the
corresponding attribution text.
