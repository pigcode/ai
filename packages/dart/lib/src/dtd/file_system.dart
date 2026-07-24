import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/errors.dart';
import 'connection.dart';
import 'models.dart';

final class DtdWorkspaceSecret {
  DtdWorkspaceSecret(String value) : _value = value {
    if (value.isEmpty) {
      throw ArgumentError.value(value, 'value', 'Must not be empty.');
    }
  }

  final String _value;

  @override
  String toString() => 'DtdWorkspaceSecret(<redacted>)';
}

final class DtdFileSystem {
  const DtdFileSystem({required this.connection});

  final DtdConnection connection;

  DtdPendingRequest setIdeWorkspaceRoots(
    DtdWorkspaceSecret secret,
    List<Uri> roots,
  ) {
    for (final root in roots) {
      _requireFileUri(root);
    }
    return connection.beginRequest(
      'FileSystem.setIDEWorkspaceRoots',
      params: <String, Object?>{
        'secret': secret._value,
        'roots': <Object?>[
          for (final root in roots) root.toString(),
        ],
      },
    );
  }

  DtdPendingRequest getIdeWorkspaceRoots() => connection.beginRequest(
        'FileSystem.getIDEWorkspaceRoots',
        params: const <String, Object?>{},
      );

  DtdPendingRequest getProjectRoots({int? depth}) {
    if (depth != null && depth < 0) {
      throw const ToolingSchemaError(
        'dtd_file_system_depth_invalid',
        'DTD project-root depth must be non-negative.',
      );
    }
    return connection.beginRequest(
      'FileSystem.getProjectRoots',
      params: <String, Object?>{if (depth != null) 'depth': depth},
    );
  }

  DtdPendingRequest readFileAsString(Uri uri) {
    _requireFileUri(uri);
    return connection.beginRequest(
      'FileSystem.readFileAsString',
      params: <String, Object?>{'uri': uri.toString()},
    );
  }

  DtdPendingRequest writeFileAsString(Uri uri, String contents) {
    _requireFileUri(uri);
    return connection.beginRequest(
      'FileSystem.writeFileAsString',
      params: <String, Object?>{
        'uri': uri.toString(),
        'contents': contents,
      },
    );
  }

  DtdPendingRequest listDirectoryContents(Uri uri) {
    _requireFileUri(uri);
    return connection.beginRequest(
      'FileSystem.listDirectoryContents',
      params: <String, Object?>{'uri': uri.toString()},
    );
  }
}

final class DtdFileContent {
  DtdFileContent._(this.value);

  factory DtdFileContent.fromResult(Map<String, Object?> result) =>
      DtdFileContent._(
        DtdModelRegistry.instance.validateResult(
          'FileSystem.readFileAsString',
          result,
        )! as JsonObject,
      );

  final JsonObject value;

  String get content => value['content']! as String;
}

final class DtdUriList {
  DtdUriList._(this.value);

  factory DtdUriList.fromResult(
    Map<String, Object?> result, {
    String method = 'FileSystem.listDirectoryContents',
  }) =>
      DtdUriList._(
        DtdModelRegistry.instance.validateResult(method, result)! as JsonObject,
      );

  final JsonObject value;

  List<Uri> get uris => List<Uri>.unmodifiable(
        (value['uris']! as List<Object?>).cast<String>().map(Uri.parse),
      );
}

final class DtdIdeWorkspaceRoots {
  DtdIdeWorkspaceRoots._(this.value);

  factory DtdIdeWorkspaceRoots.fromResult(Map<String, Object?> result) =>
      DtdIdeWorkspaceRoots._(
        DtdModelRegistry.instance.validateResult(
          'FileSystem.getIDEWorkspaceRoots',
          result,
        )! as JsonObject,
      );

  final JsonObject value;

  List<Uri> get roots => List<Uri>.unmodifiable(
        (value['ideWorkspaceRoots']! as List<Object?>)
            .cast<String>()
            .map(Uri.parse),
      );
}

void _requireFileUri(Uri uri) {
  if (uri.scheme != 'file' || !uri.hasAbsolutePath) {
    throw const ToolingSchemaError(
      'dtd_file_uri_required',
      'DTD FileSystem operation requires an absolute file URI.',
    );
  }
}
