# Dart tooling protocol support

Phase 2b records 41/41 bounded claims with one dedicated evidence item per
claim. The claim inventory covers portable LSP, DAP, Analysis Server, Dart
Tooling Daemon (DTD), and VM Service protocol state; it does not claim process,
socket, filesystem, or debugger ownership.

| Surface | Pinned profile | Verified real peers | Boundary |
| --- | --- | --- | --- |
| LSP | 3.18 audit snapshot; stable overlap by default | Dart 3.6.0, Dart 3.12.2, TypeScript Language Server 5.3.0 with TypeScript 6.0.3 | Proposed APIs require explicit opt-in; workspace edits are proposals |
| DAP | schema 1.71.0 | Dart 3.6.0, Dart 3.12.2, js-debug 1.117.0 | Adapter capabilities do not authorize terminals, processes, filesystems, or debuggees |
| Analysis Server | API 1.38.0 and 1.40.1 | exact Dart 3.6.0 and 3.12.2 revisions | Source changes are proposals |
| DTD | fixed inventory `dtd-fixed-inventory-v1` | exact Dart 3.6.0 and 3.12.2 DevTools/DTD | DTD has no wire version or version range |
| VM Service | major 4 profiles 4.16 and 4.21 | exact Dart 3.6.0 and 3.12.2 revisions | Object and isolate IDs are connection- and execution-scoped |

All transports are caller-owned transport and authorization boundaries.
Packages validate and model messages but do not start tools, open sockets,
write files, launch terminals, store credentials, or grant host permission.

The real-process evidence currently records macOS arm64. Flutter tooling is not claimed,
nor are all operating systems, CPU architectures, remote/container transports,
future protocol versions, third-party DTD service semantics, or VM Service
extensions. Protocol reconnect creates a new protocol generation and does not
restore a higher-level Agent Run.

The machine-readable source, peer, claim, evidence, and limitation closure is
in
[`compatibility/phase-2b-dart-tooling.json`](../compatibility/phase-2b-dart-tooling.json).
