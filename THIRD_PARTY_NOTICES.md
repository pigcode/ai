# Third-Party Notices

Pigcode AI uses the third-party software listed below. The versions shown were
resolved locally on 2026-07-17; the constraints in the package `pubspec.yaml`
files remain authoritative because this library workspace does not commit a
lockfile.

This notice covers direct runtime dependencies of the source SDK.
Development-only tooling (`melos`, `test`, and `lints`) is not bundled with or
redistributed as part of Pigcode AI and is therefore not included. Products
that vendor dependencies or distribute compiled artifacts must account for
every direct and transitive dependency included in that artifact.

| Package | Constraint | Audited version | License | Upstream |
| --- | --- | --- | --- | --- |
| `equatable` | `^2.0.0` | 2.1.0 | MIT | <https://pub.dev/packages/equatable> |
| `logging` | `^1.3.0` | 1.3.0 | BSD-3-Clause | <https://pub.dev/packages/logging> |
| `http` | `^1.6.0` | 1.6.0 | BSD-3-Clause | <https://pub.dev/packages/http> |
| `http_parser` | `^4.1.2` | 4.1.2 | BSD-3-Clause | <https://pub.dev/packages/http_parser> |
| `web_socket_channel` | `^3.0.3` | 3.0.3 | BSD-3-Clause | <https://pub.dev/packages/web_socket_channel> |
| `json_schema` | `^5.2.2` | 5.2.2 | Boost Software License 1.0 and embedded MIT notice | <https://pub.dev/packages/json_schema> |

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

- `logging` 1.3.0 — Copyright 2013, the Dart project authors.
- `http` 1.6.0 — Copyright 2014, the Dart project authors.
- `http_parser` 4.1.2 — Copyright 2014, the Dart project authors.
- `web_socket_channel` 3.0.3 — Copyright 2016, the Dart project authors.

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
