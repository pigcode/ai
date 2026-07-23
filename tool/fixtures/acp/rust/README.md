# Fixed Rust Testy ACP peer

The ACP peer matrix uses the official
`agentclientprotocol/rust-sdk` Testy binary at tag `v2.0.0`, exact commit
`ce023279824149008659dd8f4b8b70266a7e8210`.

The runner clones that revision under `.dart_tool/acp_peers`, builds
`agent-client-protocol-test` with `--no-default-features`, verifies the checkout
revision, and records SHA-256 digests for the resulting binary and `Cargo.lock`.
The checkout and Cargo `target` directory are never committed.
