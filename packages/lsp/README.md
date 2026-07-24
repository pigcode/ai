# Pigcode AI LSP

`pigcode_ai_lsp` is a portable, transport-independent LSP client state and
codec package. The default barrel exposes the stable overlap from the pinned
3.18 audit snapshot; proposed APIs require an explicit import from
`package:pigcode_ai_lsp/pigcode_ai_lsp_proposed.dart`.

The package models initialize/shutdown, correlation, cancellation, document
versions, capability generations, dynamic registration, progress, reverse
requests, and bounded record/replay. It accepts caller-supplied JSON messages;
it does not start a language server or own stdio.

Workspace edits and configuration requests are typed proposals. A capability
does not authorize workspace edits, file writes, commands, or any other host
effect. The caller must attach an explicit policy handler.

See [`example/portable_client.dart`](example/portable_client.dart) and the
[bounded support matrix](../../docs/dart-tooling-support.md).
