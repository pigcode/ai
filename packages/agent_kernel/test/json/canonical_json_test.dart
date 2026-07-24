import 'dart:convert';

import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  test('matches RFC 8785 number and literal serialization vectors', () {
    final value = <String, Object?>{
      'numbers': <Object?>[
        333333333.33333329,
        DomainJsonBinary64(1e30),
        4.50,
        2e-3,
        1e-27,
        -0.0,
      ],
      'literals': <Object?>[null, true, false],
    };

    expect(
      canonicalJsonEncode(value),
      '{"literals":[null,true,false],'
      '"numbers":[333333333.3333333,1e+30,4.5,0.002,1e-27,0]}',
    );
  });

  test('matches RFC 8785 binary64 exponent and fixed-form boundaries', () {
    final values = <Object?>[
      DomainJsonBinary64(5e-324),
      DomainJsonBinary64(-5e-324),
      DomainJsonBinary64(1.7976931348623157e308),
      DomainJsonBinary64(-1.7976931348623157e308),
      DomainJsonBinary64(1e21),
      DomainJsonBinary64(1e20),
      1e-6,
      1e-7,
      DomainJsonBinary64(9007199254740992.0),
    ];

    expect(
      canonicalJsonEncode(values),
      '[5e-324,-5e-324,1.7976931348623157e+308,'
      '-1.7976931348623157e+308,1e+21,100000000000000000000,'
      '0.000001,1e-7,9007199254740992]',
    );
  });

  test('sorts object keys by UTF-16 code units', () {
    final value = <String, Object?>{
      '\ue000': 2,
      '😀': 1,
    };

    expect(canonicalJsonEncode(value), '{"😀":1,"":2}');
  });

  test('uses required escaping and UTF-8 without ASCII escaping', () {
    expect(
      canonicalJsonEncode('\b\t\n\f\r"\\${String.fromCharCode(0)}€'),
      '"\\b\\t\\n\\f\\r\\"\\\\\\u0000€"',
    );
    expect(
      utf8.decode(canonicalJsonBytes(<String, Object?>{'currency': '€'})),
      '{"currency":"€"}',
    );
  });

  test('produces a stable VM and Chrome byte digest fixture', () {
    final value = <String, Object?>{'b': '€', 'a': 1};

    expect(utf8.decode(canonicalJsonBytes(value)), '{"a":1,"b":"€"}');
    expect(
      canonicalJsonSha256(value),
      '534f141d15124ffd9bd1c1e02f054020fe9918b862606c4cb5ea6dc0df5213be',
    );
  });

  test('rejects invalid values before encoding', () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);

    for (final value in <Object?>[
      cyclic,
      double.nan,
      String.fromCharCode(0xdc00),
      <Object?, Object?>{1: true},
      9007199254740992,
    ]) {
      expect(
        () => canonicalJsonEncode(value),
        throwsA(isA<DomainJsonException>()),
      );
    }
  });
}
