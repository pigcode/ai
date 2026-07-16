import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:test/test.dart';

void main() {
  group('sanitizeJsonSchema — \$ref 短路', () {
    test(r'带 $ref 的节点只保留 $ref,其余字段全部丢弃', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        r'$ref': r'#/$defs/A',
        'description': 'lost',
        'type': 'object',
      });
      expect(result, <String, Object?>{r'$ref': r'#/$defs/A'});
    });
  });

  group('sanitizeJsonSchema — 白名单原样复制', () {
    test(r'$schema/$id/title/description/enum/type 保留', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        r'$schema': 'https://json-schema.org/draft-07/schema#',
        r'$id': 'https://example.com/s',
        'title': 'T',
        'description': 'D',
        'enum': <Object?>['a', 'b'],
        'type': 'string',
      });
      expect(result, <String, Object?>{
        r'$schema': 'https://json-schema.org/draft-07/schema#',
        r'$id': 'https://example.com/s',
        'title': 'T',
        'description': 'D',
        'enum': <Object?>['a', 'b'],
        'type': 'string',
      });
    });

    test('default: null 用 containsKey 判断,保留 null 值', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'default': null,
      });
      expect(result.containsKey('default'), isTrue);
      expect(result['default'], isNull);
    });

    test('const: null 同样保留', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'const': null,
      });
      expect(result.containsKey('const'), isTrue);
      expect(result['const'], isNull);
    });

    test('default 与 const 有值时原样复制', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'default': 'x',
        'const': 'y',
      });
      expect(result['default'], 'x');
      expect(result['const'], 'y');
    });
  });

  group('sanitizeJsonSchema — oneOf → anyOf', () {
    test('oneOf 改写为 anyOf', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'oneOf': <Object?>[
          <String, Object?>{'type': 'string'},
          <String, Object?>{'type': 'number'},
        ],
      });
      expect(result.containsKey('oneOf'), isFalse);
      expect(result['anyOf'], <Object?>[
        <String, Object?>{'type': 'string'},
        <String, Object?>{'type': 'number'},
      ]);
    });

    test('anyOf 与 oneOf 同存时 oneOf 被丢弃(else-if)', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'anyOf': <Object?>[
          <String, Object?>{'type': 'string'},
        ],
        'oneOf': <Object?>[
          <String, Object?>{'type': 'number'},
        ],
      });
      expect(result['anyOf'], <Object?>[
        <String, Object?>{'type': 'string'},
      ]);
      expect(result.containsKey('oneOf'), isFalse);
    });
  });

  group('sanitizeJsonSchema — 递归清洗', () {
    test(r'allOf/definitions/$defs 逐项递归', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'allOf': <Object?>[
          <String, Object?>{'type': 'string', 'minLength': 1},
        ],
        'definitions': <String, Object?>{
          'A': <String, Object?>{
            'oneOf': <Object?>[
              <String, Object?>{'type': 'string'},
            ],
          },
        },
        r'$defs': <String, Object?>{
          'B': <String, Object?>{'type': 'number', 'minimum': 0},
        },
      });
      expect(result['allOf'], <Object?>[
        <String, Object?>{'type': 'string', 'description': 'min length: 1.'},
      ]);
      expect(result['definitions'], <String, Object?>{
        'A': <String, Object?>{
          'anyOf': <Object?>[
            <String, Object?>{'type': 'string'},
          ],
        },
      });
      expect(result[r'$defs'], <String, Object?>{
        'B': <String, Object?>{'type': 'number', 'description': 'minimum: 0.'},
      });
    });

    test('嵌套 properties 内的 oneOf 同样被改写', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'field': <String, Object?>{
            'oneOf': <Object?>[
              <String, Object?>{'type': 'string'},
            ],
          },
        },
      });
      final properties = result['properties'] as Map<String, Object?>?;
      expect(properties?['field'], <String, Object?>{
        'anyOf': <Object?>[
          <String, Object?>{'type': 'string'},
        ],
      });
    });

    test('items 数组逐项递归', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'array',
        'items': <Object?>[
          <String, Object?>{'type': 'string', 'pattern': '^a'},
          <String, Object?>{'type': 'number'},
        ],
      });
      expect(result['items'], <Object?>[
        <String, Object?>{'type': 'string', 'description': 'pattern: ^a.'},
        <String, Object?>{'type': 'number'},
      ]);
    });

    test('items 单个 schema 递归', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string', 'maxLength': 3},
      });
      expect(result['items'], <String, Object?>{
        'type': 'string',
        'description': 'max length: 3.',
      });
    });

    test('boolean 子 schema 原样保留(items: true)', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'array',
        'items': true,
      });
      expect(result['items'], isTrue);
    });
  });

  group('sanitizeJsonSchema — additionalProperties 强制 false', () {
    test('object 节点强制 additionalProperties: false 并保留 required', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'a': <String, Object?>{'type': 'string'},
        },
        'required': <Object?>['a'],
        'additionalProperties': true,
      });
      expect(result['additionalProperties'], isFalse);
      expect(result['required'], <Object?>['a']);
    });

    test('type: object 无 properties 也强制 false', () {
      final result = sanitizeJsonSchema(<String, Object?>{'type': 'object'});
      expect(result, <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
      });
    });

    test('无 type 但有 properties 也强制 false', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'properties': <String, Object?>{
          'a': <String, Object?>{'type': 'string'},
        },
      });
      expect(result['additionalProperties'], isFalse);
    });
  });

  group('sanitizeJsonSchema — format 白名单', () {
    test('白名单内 10 个 format 全部保留', () {
      const supported = <String>[
        'date-time',
        'time',
        'date',
        'duration',
        'email',
        'hostname',
        'uri',
        'ipv4',
        'ipv6',
        'uuid',
      ];
      for (final format in supported) {
        final result = sanitizeJsonSchema(<String, Object?>{
          'type': 'string',
          'format': format,
        });
        expect(result['format'], format, reason: 'format: $format');
        expect(result.containsKey('description'), isFalse);
      }
    });

    test('白名单外 format 删除并降级为 description', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'format': 'binary',
      });
      expect(result.containsKey('format'), isFalse);
      // 上游 getConstraintDescription 把 format 文本与约束文本同列 join,
      // 末尾统一加 '.'(sanitize-json-schema.ts:186)。
      expect(result['description'], 'format: binary.');
    });

    test('已有 description 时用换行拼接 format 降级文本', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'description': '原文',
        'format': 'binary',
      });
      expect(result['description'], '原文\nformat: binary.');
    });
  });

  group('sanitizeJsonSchema — 约束关键字降级', () {
    test('minLength/maxLength 消失并降级为 description', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'minLength': 2,
        'maxLength': 5,
      });
      expect(result.containsKey('minLength'), isFalse);
      expect(result.containsKey('maxLength'), isFalse);
      expect(result['description'], 'min length: 2; max length: 5.');
    });

    test('pattern 的 string 值原样进 description', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'pattern': '^a',
      });
      expect(result.containsKey('pattern'), isFalse);
      expect(result['description'], 'pattern: ^a.');
    });

    test('非 string 值用 jsonEncode(not 子 schema)', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'string',
        'not': <String, Object?>{'const': 'x'},
      });
      expect(result.containsKey('not'), isFalse);
      expect(result['description'], 'not: {"const":"x"}.');
    });

    test('uniqueItems: false 无声丢弃(falsy 不降级)', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'array',
        'uniqueItems': false,
      });
      expect(result.containsKey('uniqueItems'), isFalse);
      expect(result.containsKey('description'), isFalse);
    });

    test('uniqueItems: true 降级为 description', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'array',
        'uniqueItems': true,
      });
      expect(result['description'], 'unique items: true.');
    });

    test('已有 description 时用换行拼接约束文本', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'integer',
        'description': '原文',
        'minimum': 0,
      });
      expect(result['description'], '原文\nminimum: 0.');
    });

    test('14 个约束关键字全部不复制到输出', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'number',
        'minimum': 1,
        'maximum': 10,
        'exclusiveMinimum': 0,
        'exclusiveMaximum': 11,
        'multipleOf': 2,
        'minLength': 1,
        'maxLength': 9,
        'pattern': '^x',
        'minItems': 1,
        'maxItems': 3,
        'uniqueItems': true,
        'minProperties': 1,
        'maxProperties': 5,
        'not': <String, Object?>{'type': 'string'},
      });
      const constraintKeys = <String>[
        'minimum',
        'maximum',
        'exclusiveMinimum',
        'exclusiveMaximum',
        'multipleOf',
        'minLength',
        'maxLength',
        'pattern',
        'minItems',
        'maxItems',
        'uniqueItems',
        'minProperties',
        'maxProperties',
        'not',
      ];
      for (final key in constraintKeys) {
        expect(result.containsKey(key), isFalse, reason: 'key: $key');
      }
      expect(
        result['description'],
        'minimum: 1; maximum: 10; exclusive minimum: 0; '
        'exclusive maximum: 11; multiple of: 2; min length: 1; '
        'max length: 9; pattern: ^x; min items: 1; max items: 3; '
        'unique items: true; min properties: 1; max properties: 5; '
        'not: {"type":"string"}.',
      );
    });
  });

  group('sanitizeJsonSchema — 隐式删除', () {
    test('白名单外关键字消失且不进 description', () {
      final result = sanitizeJsonSchema(<String, Object?>{
        'type': 'object',
        'patternProperties': <String, Object?>{
          '^a': <String, Object?>{'type': 'string'},
        },
        'if': <String, Object?>{'type': 'string'},
        'then': <String, Object?>{'type': 'number'},
        'else': <String, Object?>{'type': 'boolean'},
        'examples': <Object?>['x'],
      });
      expect(result, <String, Object?>{
        'type': 'object',
        'additionalProperties': false,
      });
    });
  });
}
