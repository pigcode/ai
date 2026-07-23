# Pigcode AI ACP

A portable Dart implementation of the stable Agent Client Protocol v1
surface. It is pinned to the `schema-v1.20.0` artifact and accepts
caller-supplied transports; it does not spawn or own agent processes.

ACP has no official conformance harness, so compatibility claims are limited
to schema, scripted-peer, and fixed real-process evidence.

The `pigcode_ai_acp.dart` entrypoint is portable and accepts a caller-supplied
JSON-RPC transport. Process creation and ownership stay with the host.
Capabilities describe supported protocol operations and never grant filesystem,
terminal, or permission authority.

Run the fixed peer evidence from the workspace root:

```bash
dart run tool/run_acp_peer_matrix.dart --peer dart
dart run tool/run_acp_peer_matrix.dart --peer typescript
dart run tool/run_acp_peer_matrix.dart --peer rust
```
