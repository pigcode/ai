# Pigcode AI Protocol Utilities

Portable building blocks shared by Pigcode wire-protocol packages. The package
provides strict JSON-RPC envelopes, bounded framing, caller-supplied transports,
request correlation, and protocol-level cancellation without owning processes
or importing `dart:io`.

The API is under active Foundation development and remains `0.0.x`.

Run the local, caller-owned transport example:

```bash
dart run example/json_rpc_peer.dart
```

The example creates two in-memory peers and performs one correlated JSON-RPC
request. The package does not own a process or import `dart:io`. See the
workspace [protocol support matrix](../../docs/protocol-support.md) for the
bounded compatibility claim and known limitations.
