# Pigcode AI Agent Dart

`pigcode_ai_agent_dart` composes the portable Agent facade with Dart tooling.
All tooling processes are launched through `SandboxedProcessLauncher`.
`runInTerminal` and `workspace/applyEdit` remain typed Host proposals until an
approved Host capability executes them.

The package has no dependency on `pigcode_ai_mcp`. DAP, LSP, Analysis Server,
DTD, and VM Service protocol libraries remain authority-free.

Machine-checked Phase 4 claims:

- `P4-DART-01`: `verified`
- `P4-DART-02`: `known-unsupported`

```bash
dart run packages/agent_dart/example/dart_tooling_agent.dart
```

The dual DAP peer sandbox gate is currently known unsupported because the
peers require dynamic `bind(0)`, `node-cdp` Unix sockets, or mDNSResponder.
Pigcode does not widen the containment policy to hide that gap. See
[Native containment support](../../docs/native-containment-support.md).
