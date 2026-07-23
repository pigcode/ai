# Pigcode AI MCP

A Dart implementation of Model Context Protocol `2025-11-25` client and
server surfaces. The default and HTTP entrypoints are portable. The separate
`pigcode_ai_mcp_io.dart` entrypoint only adapts caller-owned `dart:io`
resources and is never re-exported by a portable barrel.

MCP tools and content map explicitly to the public Pigcode AI contracts.
Capabilities, annotations, roots, and session IDs are not authorization.

Use `pigcode_ai_mcp.dart` for the portable protocol core and
`pigcode_ai_mcp_http.dart` for portable Streamable HTTP and OAuth contracts.
Import `pigcode_ai_mcp_io.dart` only in VM applications that need adapters for
caller-owned processes or `dart:io` HTTP servers. The package does not bind a
socket, launch a process, open a browser, persist credentials, or authorize a
tool on the host's behalf.

The workspace pins the official conformance harness to `0.1.16`. Reproduce all
applicable MCP `2025-11-25` scenarios from the workspace root:

```bash
npm ci --prefix tool/conformance/mcp --ignore-scripts
dart run tool/run_mcp_conformance.dart --role client --suite all
dart run tool/run_mcp_conformance.dart --role server --suite all
```

The runner rejects expected-failure baselines and writes bounded machine-readable
reports under `.dart_tool/mcp_conformance`.
