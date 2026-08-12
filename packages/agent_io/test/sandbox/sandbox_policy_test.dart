import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:test/test.dart';

void main() {
  test('P4-TM-PATH-05 rejects a policy without explicit roots', () {
    expect(
      () => SandboxPolicy(roots: const <SandboxPathRule>[]),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.pathDenied,
        ),
      ),
    );
  });

  test('network allowlist accepts exact host and port only', () {
    expect(
      () => SandboxNetworkEndpoint(host: '*.example.com', port: 443),
      throwsA(
        isA<HostCapabilityException>().having(
          (error) => error.code,
          'code',
          HostCapabilityError.networkDenied,
        ),
      ),
    );
    expect(
      SandboxNetworkEndpoint(host: '127.0.0.1', port: 443).authority,
      '127.0.0.1:443',
    );
  });
}
