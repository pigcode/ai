import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../sandbox/sandbox_errors.dart';

final class CredentialScope {
  const CredentialScope({required this.host, required this.port});

  final String host;
  final int port;

  @override
  bool operator ==(Object other) =>
      other is CredentialScope && other.host == host && other.port == port;

  @override
  int get hashCode => Object.hash(host, port);
}

final class CredentialHandle {
  const CredentialHandle._(this._id);

  final String _id;

  @override
  String toString() => 'CredentialHandle(<redacted>)';
}

final class CredentialGrantBinding {
  const CredentialGrantBinding({
    required this.principalId,
    required this.policyVersion,
  });

  final String principalId;
  final int policyVersion;

  @override
  bool operator ==(Object other) =>
      other is CredentialGrantBinding &&
      other.principalId == principalId &&
      other.policyVersion == policyVersion;

  @override
  int get hashCode => Object.hash(principalId, policyVersion);
}

final class CredentialVault {
  final Map<String, _CredentialRecord> _records = <String, _CredentialRecord>{};
  final Random _random = Random.secure();

  CredentialHandle issue(
    List<int> credential, {
    required CredentialScope scope,
    required CredentialGrantBinding binding,
    Duration lifetime = const Duration(minutes: 5),
  }) {
    if (credential.isEmpty ||
        lifetime <= Duration.zero ||
        binding.principalId.isEmpty ||
        binding.policyVersion < 1) {
      throw const HostCapabilityException(
        HostCapabilityError.credentialDenied,
        'invalid-credential-grant',
      );
    }
    final id = base64Url.encode(
      List<int>.generate(24, (_) => _random.nextInt(256)),
    );
    _records[id] = _CredentialRecord(
      Uint8List.fromList(credential),
      scope,
      binding,
      DateTime.now().add(lifetime),
    );
    return CredentialHandle._(id);
  }

  Future<T> redeem<T>(
    CredentialHandle handle,
    CredentialScope scope,
    CredentialGrantBinding binding,
    Future<T> Function(Uint8List credential) operation,
  ) async {
    final record = _records[handle._id];
    if (record == null ||
        record.scope != scope ||
        record.binding != binding ||
        !DateTime.now().isBefore(record.expiresAt)) {
      throw const HostCapabilityException(
        HostCapabilityError.credentialDenied,
        'credential-handle-invalid',
      );
    }
    _records.remove(handle._id);
    final transient = Uint8List.fromList(record.credential);
    record.credential.fillRange(0, record.credential.length, 0);
    try {
      return await operation(transient);
    } finally {
      transient.fillRange(0, transient.length, 0);
    }
  }

  CredentialHandle rebindAfterRestart(
    List<int> credential, {
    required CredentialScope requestedScope,
    required CredentialGrantBinding binding,
    required Iterable<CredentialScope> allowedScopes,
    Duration lifetime = const Duration(minutes: 5),
  }) {
    if (!allowedScopes.contains(requestedScope)) {
      throw const HostCapabilityException(
        HostCapabilityError.credentialDenied,
        'credential-grant-intersection-empty',
      );
    }
    return issue(
      credential,
      scope: requestedScope,
      binding: binding,
      lifetime: lifetime,
    );
  }
}

final class _CredentialRecord {
  _CredentialRecord(
    this.credential,
    this.scope,
    this.binding,
    this.expiresAt,
  );

  final Uint8List credential;
  final CredentialScope scope;
  final CredentialGrantBinding binding;
  final DateTime expiresAt;
}
