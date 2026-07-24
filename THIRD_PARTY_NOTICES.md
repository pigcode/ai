# Third-Party Notices

Pigcode AI uses the third-party software listed below. This inventory covers
the direct runtime and development dependencies resolved on 2026-07-23. The
constraints in the package `pubspec.yaml` files remain authoritative because
this library workspace does not commit a lockfile; the audited versions are a
point-in-time record of that resolution.

Development-scope packages listed below are not bundled into SDK runtime
artifacts. Products that vendor dependencies or distribute compiled artifacts
must account for every direct and transitive dependency included in the
distributed artifact. Resolved distributions must retain the complete license
texts and copyright notices supplied with the dependencies they contain.
Future dependency resolution requires a refreshed inventory and license audit.
This notice records provenance and attribution information; it is not a legal
guarantee.

## Upstream design and adapted implementation material

Parts of Pigcode AI's API design and implementation were informed by and
adapted from the Vercel AI SDK, package `ai` 7.0.19, at pinned commit
[`e40118c48b97026ac774392e5376a11d3287e9c1`](https://github.com/vercel/ai/commit/e40118c48b97026ac774392e5376a11d3287e9c1).

Copyright 2023 Vercel, Inc.

The adapted material is licensed under the Apache License, Version 2.0. The
complete license text is available in
[`third_party/licenses/Apache-2.0.txt`](third_party/licenses/Apache-2.0.txt).
The repository copy follows the official Apache Software Foundation text at
<https://www.apache.org/licenses/LICENSE-2.0.txt>.

## Vendored protocol and conformance sources

The following fixed upstream artifacts are retained as code-generation and
compatibility inputs. Their exact repository, release, commit, byte size, and
SHA-256 tuples are locked in
[`tool/upstream/protocols/sources.json`](tool/upstream/protocols/sources.json).
They are never refreshed from an upstream default branch during a build.

- Agent Client Protocol schema and metadata, release `schema-v1.20.0`, commit
  `5e89c71497fe07dd4ae633c181a17224f4a8956d`. These artifacts are licensed
  under Apache-2.0; the upstream license is retained at
  [`tool/upstream/protocols/acp/LICENSE`](tool/upstream/protocols/acp/LICENSE),
  and the reusable license text is also available at
  [`third_party/licenses/Apache-2.0.txt`](third_party/licenses/Apache-2.0.txt).
- Model Context Protocol schema, specification release `2025-11-25`, commit
  `38c84e9f93ad191d9eb26d92b945d17bd0efcaf3`. The pinned artifact is licensed
  under MIT; its upstream notice and complete license are retained at
  [`tool/upstream/protocols/mcp/LICENSE`](tool/upstream/protocols/mcp/LICENSE).
- MCP conformance package metadata and scenario inventory, release `v0.1.16`,
  commit `21a9a2febd7100d7c17ac1021ee7f2ed9f66a1e0`. That repository records an
  Apache-2.0/MIT transition and CC-BY-4.0 terms for non-specification
  documentation. Its complete upstream licensing notice is retained at
  [`tool/upstream/protocols/mcp-conformance/LICENSE`](tool/upstream/protocols/mcp-conformance/LICENSE).
- Language Server Protocol 3.18 audit-snapshot meta-model, schema, and
  generated TypeScript comparison source, commit
  `b7f5132c95261c0898ae5124e7a91707abc48fcd`. The upstream specification and
  code license texts are retained beside the artifacts under
  [`tool/upstream/protocols/lsp/3.18-b7f5132/`](tool/upstream/protocols/lsp/3.18-b7f5132/).
- Debug Adapter Protocol schema, release `v1.71.0`, commit
  `51d95ea4e692b34c5d06601bbd1bebc1ff3fbdd4`. The upstream specification and
  code license texts are retained beside the artifacts under
  [`tool/upstream/protocols/dap/v1.71.0/`](tool/upstream/protocols/dap/v1.71.0/).
- Dart SDK Analysis Server, Dart Tooling Daemon, and VM Service protocol
  sources from releases `3.6.0` and `3.12.2`, commits
  `ae7ca5199a0559db0ae60533e9cedd3ce0d6ab04` and
  `d684a576a6aa954ae107a03b2b4e1d61c3bebe93`. These artifacts use the Dart
  SDK's BSD-3-Clause terms; the upstream license is retained at
  [`tool/upstream/protocols/dart/LICENSE`](tool/upstream/protocols/dart/LICENSE).

Exact external peer package/archive identities and integrity digests are
recorded in
[`tool/upstream/protocols/peers/phase-2b-peers.json`](tool/upstream/protocols/peers/phase-2b-peers.json).
Those peer packages are downloaded only by the compatibility harness and are
not vendored in this repository.

## Direct dependency inventory

| Package | Constraint | Audited version | Scope | License | Upstream source |
| --- | --- | --- | --- | --- | --- |
| `crypto` | `^3.0.0` | 3.0.7 | runtime + development | BSD-3-Clause | <https://github.com/dart-lang/core/tree/main/pkgs/crypto> |
| `equatable` | `^2.0.0` | 2.1.0 | runtime | MIT | <https://github.com/felangel/equatable> |
| `http` | `^1.6.0` | 1.6.0 | runtime | BSD-3-Clause | <https://github.com/dart-lang/http/tree/master/pkgs/http> |
| `http_parser` | `^4.1.2` | 4.1.2 | runtime | BSD-3-Clause | <https://github.com/dart-lang/http/tree/master/pkgs/http_parser> |
| `json_schema` | `^5.2.2` | 5.2.2 | runtime | Boost Software License 1.0 (BSL-1.0) + embedded MIT notice | <https://github.com/workiva/json_schema> |
| `logging` | `^1.3.0` | 1.3.0 | runtime | BSD-3-Clause | <https://github.com/dart-lang/core/tree/main/pkgs/logging> |
| `web_socket_channel` | `^3.0.3` | 3.0.3 | runtime | BSD-3-Clause | <https://github.com/dart-lang/http/tree/master/pkgs/web_socket_channel> |
| `lints` | `^5.0.0` | 5.1.1 | development | BSD-3-Clause | <https://github.com/dart-lang/core/tree/main/pkgs/lints> |
| `melos` | `^8.0.0` | 8.2.2 | development | Apache-2.0 | <https://github.com/invertase/melos/tree/main/packages/melos> |
| `test` | `^1.25.0` | 1.31.2 | development | BSD-3-Clause | <https://github.com/dart-lang/test/tree/master/pkgs/test> |
| `yaml` | `^3.1.3` | 3.1.3 | development | MIT | <https://github.com/dart-lang/tools/tree/main/pkgs/yaml> |

## equatable 2.1.0

MIT License

Copyright (c) 2026 Felix Angelov

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Dart project packages

The following packages use the same BSD-3-Clause terms with their respective
copyright notices:

- `logging` 1.3.0 (runtime) — Copyright 2013, the Dart project authors.
- `crypto` 3.0.7 (runtime + development) — Copyright 2015, the Dart project
  authors.
- `http` 1.6.0 (runtime) — Copyright 2014, the Dart project authors.
- `http_parser` 4.1.2 (runtime) — Copyright 2014, the Dart project authors.
- `web_socket_channel` 3.0.3 (runtime) — Copyright 2016, the Dart project
  authors.
- `lints` 5.1.1 (development) — Copyright 2021, the Dart project authors.
- `test` 1.31.2 (development) — Copyright 2014, the Dart project authors.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright
      notice, this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above
      copyright notice, this list of conditions and the following
      disclaimer in the documentation and/or other materials provided
      with the distribution.
    * Neither the name of Google LLC nor the names of its
      contributors may be used to endorse or promote products derived
      from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
"AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

## json_schema 5.2.2

In this inventory, `BSL-1.0` means the Boost Software License 1.0, not the
Business Source License.

Copyright 2013-2022 Workiva Inc.

Licensed under the Boost Software License (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.boost.org/LICENSE_1_0.txt

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

This software or document includes material copied from or derived from
JSON-Schema-Test-Suite (<https://github.com/json-schema-org/JSON-Schema-Test-Suite>),
Copyright (c) 2012 Julian Berman, which is licensed under the following terms:

    Copyright (c) 2012 Julian Berman

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in
    all copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
    THE SOFTWARE.

## yaml 3.1.3 (development)

Copyright (c) 2014, the Dart project authors.
Copyright (c) 2006, Kirill Simonov.

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
of the Software, and to permit persons to whom the Software is furnished to do
so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## melos 8.2.2 (development)

Copyright 2020 Invertase Limited

Licensed under the Apache License, Version 2.0. The complete license text is
available in
[`third_party/licenses/Apache-2.0.txt`](third_party/licenses/Apache-2.0.txt).
