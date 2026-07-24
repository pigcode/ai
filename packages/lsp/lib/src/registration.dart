import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

import 'errors.dart';
import 'method.dart';

/// One server-requested LSP dynamic registration.
final class LspDynamicRegistration {
  const LspDynamicRegistration({
    required this.id,
    required this.method,
    this.registerOptions,
  });

  final String id;
  final String method;
  final JsonValue registerOptions;

  LspDynamicRegistration freeze() {
    if (id.isEmpty) {
      throw const LspRegistrationException(
        'lsp_registration_id_empty',
        'LSP registration id must be non-empty.',
        registrationId: '',
      );
    }
    if (!lspMethodsByName.containsKey(method)) {
      throw LspRegistrationException(
        'lsp_registration_method_unknown',
        'LSP registration method is not in the pinned inventory.',
        registrationId: id,
      );
    }
    return LspDynamicRegistration(
      id: id,
      method: method,
      registerOptions: freezeJsonValue(registerOptions),
    );
  }
}
