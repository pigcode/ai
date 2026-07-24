import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import '../common/availability.dart';
import '../common/errors.dart';
import 'models.dart';
import 'version.dart';

/// Immutable protocol availability and client-advertisement snapshot.
///
/// This describes what can be represented on the wire. It deliberately does
/// not grant the server permission to act on host resources.
final class AnalysisServerCapabilitySnapshot {
  AnalysisServerCapabilitySnapshot._({
    required this.connectionId,
    required this.generation,
    required this.apiVersion,
    required this.clientCapabilities,
    required this.advertisedClientRequests,
  });

  factory AnalysisServerCapabilitySnapshot.negotiated({
    required int connectionId,
    required AnalysisServerApiVersion apiVersion,
    Map<String, Object?> clientCapabilities = const <String, Object?>{},
  }) {
    if (!analysisServerVersionPolicy.supports(apiVersion)) {
      throw const ToolingVersionError(
        'analysis_server_api_version_unsupported',
        'Analysis Server capability snapshot requires a supported API version.',
      );
    }
    final requests = clientCapabilities['requests'];
    if (requests != null &&
        (requests is! List<Object?> ||
            requests.any((request) => request is! String))) {
      throw const ToolingCapabilityError(
        'analysis_server_client_requests_invalid',
        'Analysis Server client request capabilities must be strings.',
      );
    }
    final supportsUris = clientCapabilities['supportsUris'];
    if (supportsUris != null && supportsUris is! bool) {
      throw const ToolingCapabilityError(
        'analysis_server_supports_uris_invalid',
        'Analysis Server supportsUris capability must be a boolean.',
      );
    }
    final lspCapabilities = clientCapabilities['lspCapabilities'];
    if (lspCapabilities != null && lspCapabilities is! Map<String, Object?>) {
      throw const ToolingCapabilityError(
        'analysis_server_lsp_capabilities_invalid',
        'Analysis Server LSP capabilities must be an object.',
      );
    }
    final values = freezeJsonObject(clientCapabilities);
    return AnalysisServerCapabilitySnapshot._(
      connectionId: connectionId,
      generation: 1,
      apiVersion: apiVersion,
      clientCapabilities: values,
      advertisedClientRequests: Set<String>.unmodifiable(
        (values['requests'] as List<Object?>? ?? const <Object?>[])
            .cast<String>(),
      ),
    );
  }

  final int connectionId;
  final int generation;
  final AnalysisServerApiVersion apiVersion;
  final JsonObject clientCapabilities;
  final Set<String> advertisedClientRequests;

  bool get supportsUris => clientCapabilities['supportsUris'] == true;

  bool supportsRequest(String method) =>
      AnalysisServerModelRegistry.instance.isRequestAvailable(
        method,
        apiVersion,
      );

  bool supportsNotification(String event) =>
      AnalysisServerModelRegistry.instance.isNotificationAvailable(
        event,
        apiVersion,
      );

  bool advertisesClientRequest(String method) =>
      advertisedClientRequests.contains(method);
}
