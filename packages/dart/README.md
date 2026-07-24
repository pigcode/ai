# Pigcode AI Dart Tooling

`pigcode_ai_dart` provides three portable, caller-driven protocol entrypoints:
Analysis Server API 1.38.0/1.40.1, a fixed Dart Tooling Daemon inventory, and
VM Service major 4 profiles 4.16/4.21.

DTD has no wire-version range. Its compatibility identity is the pinned SDK
revision plus `dtd-fixed-inventory-v1`; custom services remain validated
extensions rather than generally verified semantics.

Analysis Server edits and DTD filesystem operations are typed RPC/proposal
surfaces only. VM Service object IDs are not durable: Sentinel results,
isolate exit, execution generations, ID-zone invalidation, reconnect, and
disconnect can invalidate them. The package does not open WebSockets, spawn
Dart tools, write files, or authorize host effects.

See [`example/tooling_clients.dart`](example/tooling_clients.dart) and the
[bounded support matrix](../../docs/dart-tooling-support.md).
