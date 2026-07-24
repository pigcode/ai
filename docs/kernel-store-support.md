# Kernel and Store support

Phase 3 provides a portable event-sourced Agent Kernel and a VM-only
`FileAgentStore`. The machine-readable source of truth is
[`compatibility/phase-3-kernel-store.json`](../compatibility/phase-3-kernel-store.json):
28 claims have exactly 28 evidence records. Twenty-six claims are
`implemented`; only cooperative cross-process writer fencing and the
process-crash matrix are `verified`.

## Supported boundary

| Area | Supported behavior |
| --- | --- |
| Kernel | Typed 160-bit IDs, immutable AgentEvent v1, deterministic replay, one active Run, terminal barriers, cancellation, suspend/resume/reconcile, policy and approvals, owned deferred work/resources, bounded event subscriptions, stable errors, and credential-marker rejection. |
| Store consistency | Root and Session compare-and-swap, atomic batches, SHA-256 chains, sealed corruption detection, exact identity/command registries, immutable snapshots/manifests, and validated recovery fallback. |
| Process crash | `processCrashFlush` append/snapshot/compaction behavior is exercised by a fixed 12-scenario real child-process SIGKILL matrix. |
| Retention | `retainAll` is default. `pruneThroughSnapshot` is explicit, requires a safe covering snapshot and atomic batch boundary, records a prefix commitment, and advances `historyFloorSequence`. |
| Security boundary | Typed paths, root confinement, symlink/non-regular rejection, owner-only production root policy on the supported POSIX reference path, bounded payload/replay/recovery/registry/lock work, and redacted diagnostics. |
| Recorded evidence tuple | Dart `^3.6.0`, macOS arm64, local filesystem, cooperative Dart writers. CI repeats repository gates on Ubuntu, but the manifest does not turn that into an unrecorded platform support claim. |

`processCrashFlush` means that a complete artifact reached
`RandomAccessFile.flush()` before the receipt. It is evidence for process exit
and SIGKILL recovery under the supported local-filesystem contract. It is not a
claim about sudden power loss, hardware caches, or portable directory fsync.

Snapshots accelerate recovery; they do not erase facts. After explicit
physical pruning, recovery verifies the prefix commitment, snapshot digest and
registry roots, then replays the retained suffix. It does not claim to replay
deleted history. An old public cursor fails with `cursorCompacted`.

Root-scoped Session IDs and create-session command receipts, plus Session-scoped
identity and accepted-command entries, are exact monotonic registries. They
survive compaction and garbage collection. A configured entry or byte limit is
checked before allocation and Journal publication.

## Known unsupported

- Raw-device power-loss and directory-fsync durability.
- Malicious-root protection, signed journals, and rollback prevention.
- Encryption at rest and key rotation.
- Network or remote filesystems.
- Protection from non-cooperative writers that bypass the advisory lock.
- Host workspace-path, process, network, and sandbox enforcement.
- A production Driver and durable-checkpoint end-to-end journey.
- Persistent or “always allow” approvals.
- Platform support not named by an executed evidence tuple.
- Future AgentEvent or Store format migration.

These are active limitations, not implied features. The Kernel policy decides
what may be accepted, but production containment belongs to the later Host
phase.

## Reproduce the Phase 3 gates

```bash
dart run tool/check_agent_kernel_schema.dart
dart run tool/test/agent_store_multi_process_test.dart
dart run tool/run_agent_store_crash_matrix.dart --suite all
dart run tool/test/agent_kernel_secret_scan_test.dart
dart run tool/check_kernel_store_compatibility.dart
dart test packages/agent_kernel
dart test packages/agent_io
```
