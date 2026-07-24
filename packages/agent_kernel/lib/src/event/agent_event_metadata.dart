import '../json/domain_json.dart';

const registeredAgentEventMetadataNamespaces = <String>{
  'pigcode.audit',
  'pigcode.driver',
  'pigcode.policy',
  'pigcode.store',
  'adapter.acp',
  'adapter.mcp',
  'adapter.lsp',
  'adapter.dap',
  'adapter.dart',
};

final RegExp _secretKeyPattern = RegExp(
  r'authorization|credential|api[-_]?key|private[-_]?key|secret|token',
  caseSensitive: false,
);

final List<RegExp> _secretValuePatterns = <RegExp>[
  RegExp(r'-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----'),
  RegExp(r'github_pat_[A-Za-z0-9_]{20,}'),
  RegExp(r'gh[pousr]_[A-Za-z0-9]{30,}'),
  RegExp(r'sk-ant-[A-Za-z0-9_-]{20,}'),
  RegExp(r'sk-[A-Za-z0-9_-]{24,}'),
  RegExp(r'AKIA[0-9A-Z]{16}'),
  RegExp(r'\bBearer\s+\S+', caseSensitive: false),
];

final class AgentEventCodecException extends FormatException {
  AgentEventCodecException(
    this.code,
    String message, {
    this.cause,
  }) : super(message);

  final String code;
  final Object? cause;

  @override
  String toString() => 'AgentEventCodecException($code): $message';
}

final class AgentEventMetadata {
  AgentEventMetadata.fromJson(
    Map<String, Object?> value, {
    Set<String> registeredNamespaces = registeredAgentEventMetadataNamespaces,
  }) : _value = _validateAndFreeze(value, registeredNamespaces);

  AgentEventMetadata.empty() : _value = const <String, Object?>{};

  final Map<String, Object?> _value;

  Map<String, Object?> toJson() => _value;
}

Map<String, Object?> _validateAndFreeze(
  Map<String, Object?> value,
  Set<String> registeredNamespaces,
) {
  for (final namespace in value.keys) {
    if (!registeredNamespaces.contains(namespace)) {
      throw AgentEventCodecException(
        'unknown_metadata_namespace',
        'AgentEvent metadata namespace is not registered.',
      );
    }
  }

  late final Map<String, Object?> frozen;
  try {
    frozen = DomainJson.freeze(value)! as Map<String, Object?>;
  } on DomainJsonException catch (error) {
    throw AgentEventCodecException(
      'invalid_metadata_json',
      'AgentEvent metadata is not valid domain JSON.',
      cause: error,
    );
  }
  validateSafePersistedJson(frozen);
  return frozen;
}

void validateSafePersistedText(String value) {
  if (_secretValuePatterns.any((pattern) => pattern.hasMatch(value))) {
    throw AgentEventCodecException(
      'metadata_secret_rejected',
      'Persisted diagnostic text contains a credential marker.',
    );
  }
}

/// Rejects credential-shaped values and credential-bearing object keys before
/// domain JSON crosses a persistence boundary.
void validateSafePersistedJson(Object? value) {
  if (value is String) {
    validateSafePersistedText(value);
  } else if (value is List<Object?>) {
    for (final item in value) {
      validateSafePersistedJson(item);
    }
  } else if (value is Map<String, Object?>) {
    for (final entry in value.entries) {
      if (_secretKeyPattern.hasMatch(entry.key)) {
        throw AgentEventCodecException(
          'metadata_secret_rejected',
          'Persisted metadata contains a credential-bearing key.',
        );
      }
      validateSafePersistedJson(entry.value);
    }
  }
}
