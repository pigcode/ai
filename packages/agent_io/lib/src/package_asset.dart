import 'dart:isolate';
import 'dart:io';

import 'sandbox/sandbox_errors.dart';

Future<String> resolveAgentIoPackageAsset(
  String libraryRelativePath, {
  String? overridePath,
}) async {
  if (overridePath != null) return File(overridePath).absolute.path;
  final uri = await Isolate.resolvePackageUri(
    Uri.parse('package:pigcode_ai_agent_io/$libraryRelativePath'),
  );
  if (uri == null || uri.scheme != 'file') {
    throw const HostCapabilityException(
      HostCapabilityError.sandboxUnavailable,
      'agent-io-package-asset-unavailable',
    );
  }
  return File.fromUri(uri).path;
}
