import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('CacheControlValidator.getCacheControl — 读取与透传', () {
    test('从 anthropic.cacheControl 读取并原样返回', () {
      final validator = CacheControlValidator();
      final result = validator.getCacheControl(
        <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{'type': 'ephemeral'},
          },
        },
        contextType: 'system message',
        canCache: true,
      );
      expect(result, <String, Object?>{'type': 'ephemeral'});
      expect(validator.warnings, isEmpty);
    });

    test('从 anthropic.cache_control(snake_case)读取并原样返回', () {
      final validator = CacheControlValidator();
      final result = validator.getCacheControl(
        <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cache_control': <String, Object?>{
              'type': 'ephemeral',
              'ttl': '1h',
            },
          },
        },
        contextType: 'user message part',
        canCache: true,
      );
      expect(result, <String, Object?>{'type': 'ephemeral', 'ttl': '1h'});
    });

    test('两个字段名同存时 cacheControl 优先', () {
      final validator = CacheControlValidator();
      final result = validator.getCacheControl(
        <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{'type': 'ephemeral'},
            'cache_control': <String, Object?>{
              'type': 'ephemeral',
              'ttl': '5m',
            },
          },
        },
        contextType: 'user message part',
        canCache: true,
      );
      expect(result, <String, Object?>{'type': 'ephemeral'});
    });

    test('不做本地校验:任意 Map 原样透传不抛错', () {
      final validator = CacheControlValidator();
      final result = validator.getCacheControl(
        <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{
              'type': 'bogus',
              'whatever': 42,
            },
          },
        },
        contextType: 'user message part',
        canCache: true,
      );
      expect(result, <String, Object?>{'type': 'bogus', 'whatever': 42});
      expect(validator.warnings, isEmpty);
    });
  });

  group('CacheControlValidator.getCacheControl — 空值不计数', () {
    test('providerOptions 为 null / 无 anthropic key / 值为 null 均返回 null', () {
      final validator = CacheControlValidator();
      expect(
        validator.getCacheControl(
          null,
          contextType: 'system message',
          canCache: true,
        ),
        isNull,
      );
      expect(
        validator.getCacheControl(
          <String, Map<String, Object?>>{
            'openai': <String, Object?>{'foo': 'bar'},
          },
          contextType: 'system message',
          canCache: true,
        ),
        isNull,
      );
      expect(
        validator.getCacheControl(
          <String, Map<String, Object?>>{
            'anthropic': <String, Object?>{
              'cacheControl': null,
              'cache_control': null,
            },
          },
          contextType: 'system message',
          canCache: true,
        ),
        isNull,
      );
      expect(validator.warnings, isEmpty);

      // 空值不占 breakpoint 计数:其后 4 个有效值仍全部通过。
      for (var i = 0; i < 4; i++) {
        expect(
          validator.getCacheControl(
            <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'cacheControl': <String, Object?>{'type': 'ephemeral'},
              },
            },
            contextType: 'user message part',
            canCache: true,
          ),
          isNotNull,
          reason: 'valid breakpoint #${i + 1} should pass',
        );
      }
      expect(validator.warnings, isEmpty);
    });
  });

  group('CacheControlValidator.getCacheControl — canCache=false', () {
    test('返回 null 并追加 warning,不占计数', () {
      final validator = CacheControlValidator();
      final result = validator.getCacheControl(
        <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{'type': 'ephemeral'},
          },
        },
        contextType: 'thinking block',
        canCache: false,
      );
      expect(result, isNull);
      expect(validator.warnings, hasLength(1));
      expect(
        validator.warnings.single,
        const UnsupportedWarning(
          'cache_control on non-cacheable context',
          details: 'cache_control cannot be set on thinking block. '
              'It will be ignored.',
        ),
      );

      // 不计数:其后仍可用满 4 个 breakpoint。
      for (var i = 0; i < 4; i++) {
        expect(
          validator.getCacheControl(
            <String, Map<String, Object?>>{
              'anthropic': <String, Object?>{
                'cacheControl': <String, Object?>{'type': 'ephemeral'},
              },
            },
            contextType: 'user message part',
            canCache: true,
          ),
          isNotNull,
          reason: 'valid breakpoint #${i + 1} should pass',
        );
      }
      expect(validator.warnings, hasLength(1));
    });
  });

  group('CacheControlValidator.getCacheControl — 4-breakpoint 上限', () {
    ProviderOptions options() => <String, Map<String, Object?>>{
          'anthropic': <String, Object?>{
            'cacheControl': <String, Object?>{'type': 'ephemeral'},
          },
        };

    test('第 5 次起返回 null + 超限 warning,found 继续递增', () {
      final validator = CacheControlValidator();
      for (var i = 0; i < 4; i++) {
        expect(
          validator.getCacheControl(
            options(),
            contextType: 'user message part',
            canCache: true,
          ),
          <String, Object?>{'type': 'ephemeral'},
          reason: 'breakpoint #${i + 1} should pass',
        );
      }
      expect(validator.warnings, isEmpty);

      // 第 5 次:超限,返回 null + warning(found 5)。
      expect(
        validator.getCacheControl(
          options(),
          contextType: 'user message part',
          canCache: true,
        ),
        isNull,
      );
      expect(validator.warnings, hasLength(1));
      expect(
        validator.warnings.last,
        const UnsupportedWarning(
          'cacheControl breakpoint limit',
          details: 'Maximum 4 cache breakpoints exceeded (found 5). '
              'This breakpoint will be ignored.',
        ),
      );

      // 第 6 次:超限继续计数,found 为 6(spec 疑点 #9 = 照上游)。
      expect(
        validator.getCacheControl(
          options(),
          contextType: 'user message part',
          canCache: true,
        ),
        isNull,
      );
      expect(validator.warnings, hasLength(2));
      expect(
        validator.warnings.last,
        const UnsupportedWarning(
          'cacheControl breakpoint limit',
          details: 'Maximum 4 cache breakpoints exceeded (found 6). '
              'This breakpoint will be ignored.',
        ),
      );
    });

    test('计数跨调用共享于同一实例;新实例归零', () {
      final first = CacheControlValidator();
      for (var i = 0; i < 5; i++) {
        first.getCacheControl(
          options(),
          contextType: 'user message part',
          canCache: true,
        );
      }
      expect(first.warnings, hasLength(1));

      // 新实例计数归零:再用满 4 个无 warning。
      final second = CacheControlValidator();
      for (var i = 0; i < 4; i++) {
        expect(
          second.getCacheControl(
            options(),
            contextType: 'user message part',
            canCache: true,
          ),
          isNotNull,
        );
      }
      expect(second.warnings, isEmpty);
    });
  });
}
