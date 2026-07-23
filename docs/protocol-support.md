# Protocol support

Pigcode protocol packages are pre-release Foundation components. Claims in
this document are bounded by the machine-readable
[`phase-2a-protocol-foundation.json`](../compatibility/phase-2a-protocol-foundation.json)
manifest and its pinned source, peer, artifact, platform, and commit tuples.

## Support matrix

| Surface | Version | Role / transport | Claim | Evidence |
| --- | --- | --- | --- | --- |
| Protocol utilities | JSON-RPC 2.0 | caller-supplied message/byte transport | implemented | strict codec, bounded NDJSON/Content-Length/SSE framing, correlation, cancellation, backpressure, VM/Chrome and JS/wasm compile gates |
| ACP | stable v1, `schema-v1.20.0` | client and agent over caller-supplied transport | verified | 142 definitions and 23 methods classified; schema/golden/scripted/record-replay tests; fixed Dart, TypeScript SDK `1.3.0`, and Rust SDK `v2.0.0` real-process peers |
| MCP core | `2025-11-25` | client and server over caller-supplied transport | implemented | 145 definitions classified; typed lifecycle, capabilities, feature families, reverse requests, tasks, cancellation, and record/replay tests |
| MCP stdio | `2025-11-25` | client and server over newline-delimited JSON | verified | scripted and fixed Dart real-process peers; no official stdio conformance claim |
| MCP Streamable HTTP | `2025-11-25` | Pigcode client tested by official server harness | conformant | MCP conformance `v0.1.16`, suite `all`, 18/18 applicable client-role scenarios, zero failed/skipped/expected failure |
| MCP Streamable HTTP | `2025-11-25` | Pigcode server tested by official client harness | conformant | MCP conformance `v0.1.16`, suite `all`, 32/32 applicable server-role scenarios, zero failed/skipped/expected failure |
| MCP OAuth | `2025-11-25` | portable client coordinator with caller-owned ports | conformant within the client-role scenario set | protected-resource and authorization metadata, PKCE S256, DCR/CIMD, scope retry, token endpoint authentication, and audience binding |
| MCP to Pigcode AI | `2025-11-25` | tools/resources/prompts mapping | implemented | strict and preserve-with-metadata policies, mixed/error/task/cancel/schema/collision fixtures |

`implemented` means repository tests cover the stated behavior. `verified`
adds a fixed peer and full role/transport/version/platform tuple.
`conformant` is used only for the exact MCP official harness role and
Streamable HTTP scenario set above. ACP has no official conformance harness,
and MCP stdio is not labelled conformant.

## Entrypoints and ownership

- `pigcode_ai_protocol_utils.dart`, `pigcode_ai_acp.dart`,
  `pigcode_ai_mcp.dart`, and `pigcode_ai_mcp_http.dart` are portable.
- `pigcode_ai_mcp_io.dart` is VM-only and adapts caller-owned `Process`,
  `HttpServer`, and `HttpRequest` objects.
- Protocol packages do not spawn or kill processes, bind or close servers,
  launch browsers, persist credentials, select workspaces, authorize tools, or
  enforce a sandbox.
- Capabilities and MCP tool annotations describe protocol behavior; they do
  not grant host authority.

## Known unsupported or deliberately bounded behavior

- JSON-RPC batch envelopes are rejected.
- ACP experimental or draft artifacts outside pinned stable
  `schema-v1.20.0` are not public claims.
- ACP session resume is protocol resume, not a claim of live runtime attach or
  durable checkpoint recovery.
- MCP stdio has Pigcode contract and real-process evidence only because the
  pinned official harness covers Streamable HTTP.
- Unknown MCP prompt/content mapping variants are rejected by the strict
  mapping policy; preserve mode retains supported lossy metadata but never
  dereferences resource links.
- Process lifecycle, socket binding, browser interaction, credential storage,
  workspace authority, and production containment remain caller concerns and
  later Foundation phase work.

## Reproducing the evidence

From the workspace root:

```bash
dart pub get
dart run tool/test/protocol_sources_test.dart
dart run tool/test/protocol_inventory_test.dart
dart run tool/test/protocol_codegen_test.dart
dart run tool/test/protocol_compatibility_manifest_test.dart
dart run tool/test/protocol_fixture_coverage_test.dart
dart run tool/check_protocol_compatibility.dart
dart run tool/run_acp_peer_matrix.dart --peer dart
dart run tool/run_acp_peer_matrix.dart --peer typescript
dart run tool/run_acp_peer_matrix.dart --peer rust
npm ci --prefix tool/conformance/mcp --ignore-scripts
dart run tool/run_mcp_conformance.dart --role client --suite all
dart run tool/run_mcp_conformance.dart --role server --suite all
```
