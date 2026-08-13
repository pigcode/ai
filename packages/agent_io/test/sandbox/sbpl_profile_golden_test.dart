import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

import '../support/workspace_path.dart';

void main() {
  test('policy produces a stable default-deny SBPL profile', () {
    final profile = SbplProfile.generate(
      SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: '/workspace/read-only',
            access: SandboxPathAccess.readOnly,
          ),
          SandboxPathRule(
            path: '/workspace/read-write',
            access: SandboxPathAccess.readWrite,
          ),
        ],
        networkAllowlist: <SandboxNetworkEndpoint>[
          SandboxNetworkEndpoint(host: 'localhost', port: 4317),
        ],
        denyReadPaths: const <String>['/Users/example/.ssh'],
      ),
    );
    final golden = File(
      resolveTestWorkspacePath(
        packageRelative: 'test/fixtures/sbpl/basic.sb',
        workspaceRelative: 'packages/agent_io/test/fixtures/sbpl/basic.sb',
      ),
    ).readAsStringSync();

    expect(profile, golden);
  });

  test('SBPL path escaping handles quotes newlines and non-ASCII safely', () {
    final profile = SbplProfile.generate(
      SandboxPolicy(
        roots: <SandboxPathRule>[
          SandboxPathRule(
            path: '/tmp/引号"和\n换行',
            access: SandboxPathAccess.readOnly,
          ),
        ],
      ),
    );

    expect(profile, contains(r'/tmp/引号\"和\n换行'));
    expect(profile, isNot(contains('和\n换行')));
  });

  test('SBPL rejects paths containing unrepresentable control characters', () {
    expect(
      () => SbplProfile.generate(
        SandboxPolicy(
          roots: <SandboxPathRule>[
            SandboxPathRule(
              path: '/tmp/control\u0001',
              access: SandboxPathAccess.readOnly,
            ),
          ],
        ),
      ),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.pathDenied,
        ),
      ),
    );
  });
}
