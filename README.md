# Pigcode AI

A pure-Dart AI SDK with neutral model contracts, streaming, tool calling,
structured output, middleware, telemetry, and provider adapters.

The repository is a Dart workspace. Package directories stay short while each
public package identity uses the `pigcode_ai_*` namespace.

## Packages

- `pigcode_ai_provider` — neutral model and provider contracts.
- `pigcode_ai_provider_utils` — shared provider transport and validation utilities.
- `pigcode_ai` — high-level generation, streaming, tool-loop, middleware, and telemetry APIs.
- `pigcode_ai_openai` — OpenAI wire adapter.
- `pigcode_ai_openai_compatible` — configurable OpenAI-compatible wire adapter.
- `pigcode_ai_anthropic` — Anthropic wire adapter.

Only these six packages are implemented in the current tree. Development Agent,
protocol, and harness packages will be added as tested vertical slices.

## Development

```bash
dart pub get
dart run melos format
dart run melos analyze
dart run melos test
```

All packages remain `publish_to: none` during foundation development.
