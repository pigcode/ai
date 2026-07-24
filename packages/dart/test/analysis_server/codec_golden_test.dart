import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('NDJSON request, response, and notification round-trip', () {
    final request = AnalysisServerCodec.instance.decodeLine(
      '{"id":"1","method":"analysis.setAnalysisRoots",'
      '"params":{"included":["/workspace"],"excluded":[]}}',
    );
    expect(request.kind, AnalysisServerMessageKind.request);
    expect(request.name, 'analysis.setAnalysisRoots');

    final response = AnalysisServerCodec.instance.decodeLine(
      '{"id":"1","result":{"version":"1.40.1"}}',
      requestMethod: 'server.getVersion',
    );
    expect(response.kind, AnalysisServerMessageKind.response);
    expect(response.name, 'server.getVersion');

    final notification = AnalysisServerCodec.instance.decodeLine(
      '{"event":"server.connected",'
      '"params":{"version":"1.40.1","pid":42}}',
    );
    expect(notification.kind, AnalysisServerMessageKind.notification);
    expect(notification.name, 'server.connected');
  });

  test('invalid envelope and payload shapes are rejected', () {
    expect(
      () => AnalysisServerCodec.instance.decodeLine(
        '{"id":"1","method":"analysis.setAnalysisRoots",'
        '"params":{"included":[42],"excluded":[]}}',
      ),
      throwsA(isA<ToolingSchemaError>()),
    );
    expect(
      () => AnalysisServerCodec.instance.decodeLine(
        '{"id":"1","method":"unknown.method"}',
      ),
      throwsA(isA<ToolingCodecError>()),
    );
    expect(
      () => AnalysisServerCodec.instance.decodeLine(
        '{"event":"server.connected",'
        '"params":{"version":"1.40.1","pid":42}}\n'
        '{"event":"server.connected","params":{}}',
      ),
      throwsA(isA<ToolingFramingError>()),
    );
  });
}
