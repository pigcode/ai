import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('FileSystem operations only create typed RPC requests', () {
    final client = DtdClient();
    final secret = DtdWorkspaceSecret('opaque-value');
    final roots = client.fileSystem.setIdeWorkspaceRoots(
      secret,
      <Uri>[Uri(scheme: 'file', path: '/workspace/')],
    );
    expect(roots.method, 'FileSystem.setIDEWorkspaceRoots');
    expect(roots.params['roots'], <Object?>['file:///workspace/']);

    final write = client.fileSystem.writeFileAsString(
      Uri.parse('file:///workspace/a.txt'),
      'contents',
    );
    expect(write.method, 'FileSystem.writeFileAsString');
    expect(write.params['contents'], 'contents');

    final readResult = DtdFileContent.fromResult(
      const <String, Object?>{
        'type': 'FileContent',
        'content': 'remote contents',
      },
    );
    expect(readResult.content, 'remote contents');
  });

  test('typed FileSystem boundary rejects non-file URIs', () {
    final fileSystem = DtdClient().fileSystem;
    expect(
      () => fileSystem.readFileAsString(Uri.parse('https://example.test/a')),
      throwsA(isA<ToolingSchemaError>()),
    );
    expect(
      () => fileSystem.setIdeWorkspaceRoots(
        DtdWorkspaceSecret('opaque'),
        <Uri>[Uri(scheme: 'https', host: 'example.test')],
      ),
      throwsA(isA<ToolingSchemaError>()),
    );
  });
}
