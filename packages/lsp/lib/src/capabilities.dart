import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';
import 'registration.dart';

/// Immutable server capability and dynamic-registration generation.
final class LspCapabilitySnapshot {
  LspCapabilitySnapshot._({
    required this.connectionId,
    required this.generation,
    required this.serverCapabilities,
    required Map<String, LspDynamicRegistration> registrations,
  }) : registrations =
            Map<String, LspDynamicRegistration>.unmodifiable(registrations);

  factory LspCapabilitySnapshot.fromInitialize({
    required int connectionId,
    required int generation,
    required Map<String, Object?> serverCapabilities,
  }) {
    return LspCapabilitySnapshot._(
      connectionId: connectionId,
      generation: generation,
      serverCapabilities: freezeJsonObject(serverCapabilities),
      registrations: const <String, LspDynamicRegistration>{},
    );
  }

  final int connectionId;
  final int generation;
  final JsonObject serverCapabilities;
  final Map<String, LspDynamicRegistration> registrations;

  /// Whether the peer advertised or dynamically registered [method].
  bool supportsMethod(String method) {
    final descriptor = lspMethodsByName[method];
    if (descriptor == null) {
      return false;
    }
    if (registrations.values.any(
      (registration) => registration.method == method,
    )) {
      return true;
    }
    final capability = descriptor.serverCapability;
    if (capability == null) {
      return true;
    }
    final exact = _readPath(serverCapabilities, capability);
    if (_enabled(exact)) {
      return true;
    }
    if (capability == 'textDocumentSync.openClose') {
      return switch (serverCapabilities['textDocumentSync']) {
        final int value => value > 0,
        _ => false,
      };
    }
    return false;
  }

  LspCapabilitySnapshot register(LspDynamicRegistration registration) {
    final frozen = registration.freeze();
    if (registrations.containsKey(frozen.id)) {
      throw LspRegistrationException(
        'lsp_registration_duplicate',
        'LSP dynamic registration id is already active.',
        registrationId: frozen.id,
      );
    }
    return LspCapabilitySnapshot._(
      connectionId: connectionId,
      generation: generation + 1,
      serverCapabilities: serverCapabilities,
      registrations: <String, LspDynamicRegistration>{
        ...registrations,
        frozen.id: frozen,
      },
    );
  }

  LspCapabilitySnapshot unregister(String registrationId) {
    if (!registrations.containsKey(registrationId)) {
      throw LspRegistrationException(
        'lsp_registration_unknown',
        'LSP dynamic registration id is not active.',
        registrationId: registrationId,
      );
    }
    return LspCapabilitySnapshot._(
      connectionId: connectionId,
      generation: generation + 1,
      serverCapabilities: serverCapabilities,
      registrations: <String, LspDynamicRegistration>{
        for (final entry in registrations.entries)
          if (entry.key != registrationId) entry.key: entry.value,
      },
    );
  }
}

Object? _readPath(JsonObject root, String path) {
  Object? current = root;
  for (final segment in path.split('.')) {
    if (current is! Map<String, Object?> || !current.containsKey(segment)) {
      return null;
    }
    current = current[segment];
  }
  return current;
}

bool _enabled(Object? value) => switch (value) {
      true => true,
      final num value => value > 0,
      final String value => value.isNotEmpty,
      Map<Object?, Object?>() => true,
      List<Object?>() => true,
      _ => false,
    };
