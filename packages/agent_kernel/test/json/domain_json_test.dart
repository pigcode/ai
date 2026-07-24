import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('deep copy is immutable and detached from mutable input', () {
    final child = <Object?>['before'];
    final source = <String, Object?>{'child': child};

    final frozen = DomainJson.freeze(source)! as Map<String, Object?>;
    child[0] = 'after';
    source['new'] = true;

    expect(frozen, <String, Object?>{
      'child': <Object?>['before'],
    });
    expect(
      () => (frozen['child']! as List<Object?>).add('mutation'),
      throwsUnsupportedError,
    );
    expect(() => frozen['new'] = true, throwsUnsupportedError);
  });

  test('rejects cycles, non-string keys, unsupported values, and non-finite',
      () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);

    final cases = <Object?>[
      cyclic,
      <Object?, Object?>{1: 'not a string key'},
      DateTime.utc(2026),
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ];

    for (final value in cases) {
      expect(
        () => DomainJson.freeze(value),
        throwsA(isA<DomainJsonException>()),
        reason: '$value',
      );
    }
  });

  test('rejects unsafe integer and requires a typed string representation', () {
    expect(
      () => DomainJson.freeze(9007199254740992),
      throwsA(
        isA<DomainJsonException>().having(
          (error) => error.code,
          'code',
          DomainJsonErrorCode.unsafeInteger,
        ),
      ),
    );
    expect(DomainJson.freeze('9007199254740992'), '9007199254740992');
  });

  test('rejects lone UTF-16 surrogates', () {
    expect(
      () => DomainJson.freeze(String.fromCharCode(0xd800)),
      throwsA(
        isA<DomainJsonException>().having(
          (error) => error.code,
          'code',
          DomainJsonErrorCode.loneSurrogate,
        ),
      ),
    );
  });

  test('enforces depth, collection, string, and total-node limits', () {
    expect(
      () => DomainJson.freeze(
        <Object?>[
          <Object?>[null],
        ],
        limits: const DomainJsonLimits(maxDepth: 1),
      ),
      throwsA(_domainJsonCode(DomainJsonErrorCode.depthLimit)),
    );
    expect(
      () => DomainJson.freeze(
        <Object?>[1, 2],
        limits: const DomainJsonLimits(maxCollectionLength: 1),
      ),
      throwsA(_domainJsonCode(DomainJsonErrorCode.collectionLimit)),
    );
    expect(
      () => DomainJson.freeze(
        'ab',
        limits: const DomainJsonLimits(maxStringCodeUnits: 1),
      ),
      throwsA(_domainJsonCode(DomainJsonErrorCode.stringLimit)),
    );
    expect(
      () => DomainJson.freeze(
        <Object?>[1, 2],
        limits: const DomainJsonLimits(maxTotalNodes: 2),
      ),
      throwsA(_domainJsonCode(DomainJsonErrorCode.nodeLimit)),
    );
  });
}

Matcher _domainJsonCode(DomainJsonErrorCode code) =>
    isA<DomainJsonException>().having((error) => error.code, 'code', code);
