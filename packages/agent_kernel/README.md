# Pigcode AI Agent Kernel

`pigcode_ai_agent_kernel` is the portable, event-sourced Agent domain layer. It
contains typed opaque IDs, commands and receipts, immutable events, the
deterministic reducer, Driver fencing, policy and approval binding, terminal
barriers, public event subscriptions, and the `AgentStore` contract.

The public barrel has no `dart:io` dependency and is validated on the Dart VM
and browser compilation targets. The package does not start processes, access a
workspace, or provide a production Driver or sandbox.

Run the lifecycle example:

```bash
dart run packages/agent_kernel/example/session_run.dart
```

The example injects the package's test-only in-memory Store. It demonstrates
create-session, start-run, an authoritative terminal proposal, and replay, but
it is deliberately not durable. Use `pigcode_ai_agent_io` when persistence is
required.

See the repository's [Kernel and Store support](../../docs/kernel-store-support.md)
for the exact evidence boundary and known unsupported capabilities.
