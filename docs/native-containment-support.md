# Native containment support

Phase 4 adds a portable Native Agent facade and VM-only Host containment. The
machine-readable authority is
[`compatibility/phase-4-native-containment.json`](../compatibility/phase-4-native-containment.json).
This implementation work uses the required `pending-main-merge` evidence
sentinel; a later evidence-only change may bind it to the main merge commit.

## Fail-closed contract

Production Host execution requires a production-ready capability probe before
the child starts. Unsupported platforms, insufficient Landlock ABI, profile
compilation errors, unrepresentable policy, cleanup uncertainty, and stale
capability recovery fail with typed errors. They never fall back to
`UnsafeDevSandboxBackend`.

`UnsafeDevSandboxBackend` is labelled `unsafe/dev-only`. It is useful only for
explicit local development and cannot satisfy a production claim or evidence
gate.

## Platform evidence

- macOS arm64, macOS 13 or newer: local evidence was executed on macOS 15.6.1
  build 24G90 using Seatbelt.
- Linux x86_64/arm64: implementation requires kernel 6.7 or newer, Landlock ABI
  4 or newer, and seccomp. No Linux CI run exists in this unpushed worktree, so
  Linux remains implemented/CI-deferred and is not verified.
- Windows, macOS x86_64, Linux below the kernel/ABI floor, and all other
  platforms fail closed.

## Final claim status

The independent-review rating is 4 verified, 13 implemented, and 1
known-unsupported. Eight claims were downgraded because their current evidence
is contract/fixture evidence or leaves a production trust boundary unresolved.

Machine-checked declarations:

- `P4-HOST-01`: `implemented`
- `P4-HOST-02`: `verified`
- `P4-HOST-03`: `implemented`
- `P4-HOST-04`: `implemented`
- `P4-HOST-05`: `implemented`
- `P4-HOST-06`: `implemented`
- `P4-HOST-07`: `verified`
- `P4-HOST-08`: `implemented`
- `P4-HOST-09`: `verified`
- `P4-HOST-10`: `implemented`
- `P4-AGENT-01`: `implemented`
- `P4-AGENT-02`: `implemented`
- `P4-AGENT-03`: `implemented`
- `P4-DART-01`: `verified`
- `P4-DART-02`: `known-unsupported`
- `P4-CROSS-01`: `implemented`
- `P4-CROSS-02`: `implemented`
- `P4-CROSS-03`: `implemented`

| Claim | Level | Evidence or missing evidence |
| --- | --- | --- |
| `P4-HOST-01` | implemented | Capability contracts fail closed; a real Linux production probe/start tuple is still required (a). |
| `P4-HOST-02` | verified | Real Seatbelt children prove apply-before-exec FS/network denial. |
| `P4-HOST-03` | implemented | Landlock/seccomp requires a real Linux CI enforcement run (a). |
| `P4-HOST-04` | implemented | Lexical and device/inode alias hardening is implemented; PATH-01/03/05 remain mainly Host evidence pending independent verification. |
| `P4-HOST-05` | implemented | macOS cannot rediscover an already-detached orphan after a parent-first crash (`KU-P4-MACOS-DETACHED-CRASH-CLEANUP`) (c). |
| `P4-HOST-06` | implemented | PTY-01 and identity cleanup are real; PTY-02 is Host buffering, ABI4 ioctl is unsupported, and ABI>=5 enforcement needs Linux CI (a/c). |
| `P4-HOST-07` | verified | Git FS/network/credential/process boundaries run under Seatbelt. |
| `P4-HOST-08` | implemented | CRED-04 lacks a real persistent-grant restart and reintersection journey. |
| `P4-HOST-09` | verified | Exact TCP success, adjacent-port/non-allowlisted-IP controls and denial, macOS UDP/DNS/Unix denial, roots denial, and boundary redaction pass. |
| `P4-HOST-10` | implemented | The crash matrix consumes production recovery-coordinator results; independent verification has not re-rated the evidence. |
| `P4-AGENT-01` | implemented | Complete facade contract evidence is capped at implemented by architecture §17. |
| `P4-AGENT-02` | implemented | A closed effect registry is bound to manifest identity and trusted probe digest; independent verification has not re-rated the evidence. |
| `P4-AGENT-03` | implemented | The five paths lack one product entry and crash/restart is manually composed. |
| `P4-DART-01` | verified | Dart 3.12.2 language-server initialize/open/hover/completion/shutdown runs under Seatbelt; unapproved applyEdit leaves the file unchanged. |
| `P4-DART-02` | known-unsupported | Strict networking conflicts with dynamic DAP TCP/Unix/resolver channels (`KU-P4-DAP-POLICY`) (c). |
| `P4-CROSS-01` | implemented | The local Chrome MIME/runner gate is deferred to CI (b). |
| `P4-CROSS-02` | implemented | The 169-case mutation closure is contract evidence capped at implemented by §17. |
| `P4-CROSS-03` | implemented | Documentation/example consumption is contract evidence capped at implemented by §17. |

`P4-AGENT-02` has managed ordering, observed-only, unknown-outcome, and
anti-forgery tests, but remains implemented until the capability source chain
cannot be publicly self-reported. `P4-AGENT-03` has five fixture journeys and
Journal replay but no single product entry; crash/restart remains manually
composed. `P4-HOST-08` has real visibility, crash-scan, and exfiltration
evidence but not a persistent-grant CRED-04 restart. `P4-HOST-10` has ten
SIGKILL injections and mutations but not production-coordinator recovery
evidence. `P4-DART-02` is claim-level `known-unsupported`:
the strict-policy dual DAP journey is not achieved. The local Chrome runner
MIME issue is CI-deferred; VM, JavaScript, and WebAssembly compile gates remain
available.

`P4-HOST-09` is verified only on the recorded macOS tuple. Linux declarations
come only from a real runtime probe; this macOS run skips them rather than
constructing an ABI report. DLP-05 is a protocol/Host boundary: a real
sandboxed child emits a sensitive frame, the Host redacts it before durable
persistence, recalculates Content-Length, and revalidates the persisted JSON.
It is not represented as a kernel redaction feature.

## Roadmap section 9 exit gate

- Native Journey five paths: satisfied locally.
- Host Contract Suite path containment, process cleanup, secret redaction, and
  effect-control: not fully closed. The macOS detached-parent crash limitation
  is recorded, and Linux enforcement rows require a pushed `ubuntu-24.04` CI
  run.
- Every production-supported platform has a real sandbox: macOS arm64 is
  evidenced locally; Linux implementation exists but its production evidence
  can close only after push-triggered Linux CI.

The design's additional portable/DAP gates are also not fully closed:
Chrome remains CI-deferred, and the strict-policy dual-DAP journey is
known-unsupported rather than weakened to pass.

## Known unsupported

- `KU-P4-WINDOWS`: Windows production containment is unsupported.
- `KU-P4-MACOS-X64`: macOS x86_64 production containment is unsupported.
- `KU-P4-LINUX-LOW-ABI`: Linux below kernel 6.7 or Landlock ABI 4 fails closed.
- `KU-P4-NAMESPACE`: PID and mount namespaces are not provided; process groups
  are cleanup, not namespace isolation.
- `KU-P4-MACOS-DETACHED-CRASH-CLEANUP`: after a macOS parent is killed, an
  already-`setsid` orphan cannot be rediscovered reliably from the original
  PGID ledger; live-parent cancellation cleanup remains covered.
- `KU-P4-PTY-ABI4`: Landlock ABI 4 cannot restrict PTY ioctl/device control.
- `KU-P4-DLP-NONTCP`: abstract Unix sockets and parts of UDP/DNS bypass
  enforcement remain unsupported; measured paths are denied but not claimed
  as complete protocol isolation.
- `KU-P4-MALICIOUS-HOST`: root, administrators, and a malicious Host are
  outside the sandbox trust boundary.
- `KU-P4-EXTERNAL-HARNESS`: the exact external harness effect matrix belongs
  to Phase 5.
- `KU-P4-STRONGER-ISOLATION`: bubblewrap, gVisor, and microVM isolation are not
  implemented.
- `KU-P4-APPLE-FUTURE`: App Sandbox and Apple Containerization remain
  observation items rather than production backends.
- `KU-P4-DATA-AT-REST`: encryption at rest, production ACLs, and raw-device
  power-loss durability are not claimed.
- `KU-P4-DURABLE-CHECKPOINT`: complete production
  `durableCheckpointResume` is not claimed.
- `KU-P4-HARDLINK`: Seatbelt cannot distinguish an external inode reached
  through a hard-link alias; Host inode validation supplies the first layer.
- `KU-P4-LANDLOCK-NESTED-RO`: one Landlock ruleset cannot express a read-only
  nested `.git` under a writable parent.
- `KU-P4-DAP-POLICY`: js-debug requires `bind(0)` and
  `node-cdp.*.sock`; Dart DAP requires localhost/mDNSResponder resolution.
  Widening those channels would weaken `P4-TM-DLP-01/02/03`, so the gate is
  intentionally skipped.
- `KU-P4-CHROME-LOCAL`: the local Chrome test runner serves the portable smoke
  entrypoint with an invalid MIME type; this remains CI-deferred.
