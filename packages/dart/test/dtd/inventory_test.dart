import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('fixed DTD inventory covers core, stream, and FileSystem methods', () {
    final registry = DtdModelRegistry.instance;

    expect(registry.fixedMethodNames, hasLength(11));
    expect(
      registry.fixedMethodNames,
      containsAll(const <String>[
        'streamListen',
        'streamCancel',
        'postEvent',
        'streamNotify',
        'registerService',
        'FileSystem.readFileAsString',
        'FileSystem.writeFileAsString',
        'FileSystem.listDirectoryContents',
        'FileSystem.setIDEWorkspaceRoots',
        'FileSystem.getIDEWorkspaceRoots',
        'FileSystem.getProjectRoots',
      ]),
    );
    expect(registry.typeNames, hasLength(4));
    expect(registry.errorCodes, hasLength(11));
  });

  test('every fixed method validates positive and negative payloads', () {
    final registry = DtdModelRegistry.instance;
    final valid = <String, Map<String, Object?>>{
      'streamListen': <String, Object?>{'streamId': 'Service'},
      'streamCancel': <String, Object?>{'streamId': 'Service'},
      'postEvent': <String, Object?>{
        'streamId': 'Service',
        'eventKind': 'changed',
        'eventData': <String, Object?>{},
      },
      'registerService': <String, Object?>{
        'service': 'Example',
        'method': 'ping',
      },
      'streamNotify': <String, Object?>{
        'streamId': 'Service',
        'eventKind': 'changed',
        'eventData': <String, Object?>{},
      },
      'FileSystem.readFileAsString': <String, Object?>{
        'uri': 'file:///workspace/a.txt',
      },
      'FileSystem.writeFileAsString': <String, Object?>{
        'uri': 'file:///workspace/a.txt',
        'contents': 'value',
      },
      'FileSystem.listDirectoryContents': <String, Object?>{
        'uri': 'file:///workspace/',
      },
      'FileSystem.setIDEWorkspaceRoots': <String, Object?>{
        'secret': 'opaque',
        'roots': <Object?>['file:///workspace/'],
      },
      'FileSystem.getIDEWorkspaceRoots': <String, Object?>{},
      'FileSystem.getProjectRoots': <String, Object?>{'depth': 4},
    };

    for (final method in registry.fixedMethodNames) {
      expect(
        registry.validateParams(method, valid[method]),
        isA<Map<String, Object?>>(),
        reason: method,
      );
      expect(
        () => registry.validateParams(
          method,
          <String, Object?>{'unexpected': true},
        ),
        throwsA(isA<ToolingSchemaError>()),
        reason: method,
      );
    }
  });
}
