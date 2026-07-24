# Pigcode AI Agent IO

`pigcode_ai_agent_io` is the VM-only reference implementation of the Agent
Store contract. `FileAgentStore` uses immutable generations, framed SHA-256
Journal records, exact identity and command registries, snapshots, cooperative
writer fencing, and typed recovery failures.

The default durability is `processCrashFlush`: complete artifacts are flushed
before a receipt is returned and are covered by real-process SIGKILL evidence.
It does not claim raw-device power-loss durability or portable directory fsync.

`retainAll` is the default retention policy. Physical pruning requires the
explicit `pruneThroughSnapshot` policy, a safe covering snapshot, and an atomic
batch boundary. Old cursors then receive `cursorCompacted`. Exact root and
Session identity/command registries remain monotonic; reaching their hard limit
fails closed before a new allocation or Journal append.

Production mode requires a private owner-only Store root on the supported POSIX
reference platforms. `FileStoreRootAccessPolicy.explicitTestOnly` is an
explicit testing escape hatch, not a production permission claim.

Run the durable example:

```bash
dart run packages/agent_io/example/durable_store.dart
```

It uses a caller-owned temporary root, appends, snapshots, reopens, and removes
only that temporary root. See [Kernel and Store support](../../docs/kernel-store-support.md)
for supported and unsupported boundaries.
