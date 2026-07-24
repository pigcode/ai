import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('workspace secret never enters strings, errors, or diagnostics', () {
    const rawSecret = 'never-render-this-secret';
    final secret = DtdWorkspaceSecret(rawSecret);
    final request = DtdClient().fileSystem.setIdeWorkspaceRoots(
      secret,
      <Uri>[Uri(scheme: 'file', path: '/workspace/')],
    );
    const redactor = DartToolingDiagnosticRedactor();
    final diagnostic = redactor.redact(<String, Object?>{
      'method': request.method,
      'secret': rawSecret,
    });
    const error = ToolingProtocolStateError(
      'dtd_failure',
      'DTD operation failed.',
    );

    expect(secret.toString(), isNot(contains(rawSecret)));
    expect(request.toString(), isNot(contains(rawSecret)));
    expect(error.toString(), isNot(contains(rawSecret)));
    expect(diagnostic.toString(), isNot(contains(rawSecret)));
  });
}
