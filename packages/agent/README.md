# Pigcode AI Agent

`pigcode_ai_agent` is the portable facade for explicit, durable Agent Sessions.
It exposes `DevelopmentAgent`, `NativeAgentDriver`, AI SDK event mapping, and
Host capability ports without importing `dart:io`, Flutter, protocol packages,
or the VM-only containment implementation.

Every generation call requires an `AgentSessionProjection`; there is no hidden
one-shot Session. Managed effects are write-ahead WorkItems, interceptable
reverse requests remain proposals, observed-only effects receive no managed
approval evidence, and unknown outcomes are never replayed.

Host side effects belong in `pigcode_ai_agent_io`, while Dart tooling
composition belongs in `pigcode_ai_agent_dart`.

Machine-checked Phase 4 claims:

- `P4-AGENT-01`: `implemented`
- `P4-AGENT-02`: `implemented`
- `P4-AGENT-03`: `implemented`

```bash
dart run packages/agent/example/native_agent.dart
```

See [Native containment support](../../docs/native-containment-support.md) for
the evidence-backed platform matrix and known unsupported scope.
