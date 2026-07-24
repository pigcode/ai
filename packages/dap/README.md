# Pigcode AI DAP

`pigcode_ai_dap` provides portable DAP 1.71.0 models, codecs, capability and
session state, cancellation, progress, reference lifetimes, and bounded
record/replay. It operates over a caller-owned transport and does not start or
manage an adapter.

`runInTerminal` and `startDebugging` are typed proposals. The package does not launch processes or terminals, write files, control a debuggee, or treat an
adapter capability as host authorization.

See [`example/portable_client.dart`](example/portable_client.dart) and the
[bounded support matrix](../../docs/dart-tooling-support.md).
