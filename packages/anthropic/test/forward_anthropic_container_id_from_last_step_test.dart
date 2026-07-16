import 'package:pigcode_ai_anthropic/pigcode_ai_anthropic.dart';
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:test/test.dart';

void main() {
  group('forwardAnthropicContainerIdFromLastStep', () {
    test('命中:container id 以标准 providerOptions 形态返回', () {
      final result = forwardAnthropicContainerIdFromLastStep(
        <ProviderMetadata?>[
          {
            'anthropic': {
              'container': {'id': 'container_a'},
            },
          },
        ],
      );

      expect(result, {
        'anthropic': {
          'container': {'id': 'container_a'},
        },
      });
    });

    test('倒序穿透:null 项/无 container 项/空串 id 被跳过,取最近命中', () {
      final result = forwardAnthropicContainerIdFromLastStep(
        <ProviderMetadata?>[
          {
            'anthropic': {
              'container': {'id': 'container_old'},
            },
          },
          {
            'anthropic': {
              'container': {'id': 'container_new'},
            },
          },
          null,
          {
            'anthropic': {'usage': <String, Object?>{}},
          },
          {
            'anthropic': {
              'container': {'id': ''},
            },
          },
        ],
      );

      // 倒序:空串 id(未命中)→ 无 container 项 → null 项 →
      // container_new 命中,不再回溯到 container_old。
      expect(result, {
        'anthropic': {
          'container': {'id': 'container_new'},
        },
      });
    });

    test('无命中三态:空列表 / 全 null / id 缺席、空串或非 String', () {
      expect(
        forwardAnthropicContainerIdFromLastStep(const <ProviderMetadata?>[]),
        isNull,
      );
      expect(
        forwardAnthropicContainerIdFromLastStep(
          <ProviderMetadata?>[null, null],
        ),
        isNull,
      );
      expect(
        forwardAnthropicContainerIdFromLastStep(
          <ProviderMetadata?>[
            {
              'anthropic': {'container': <String, Object?>{}},
            },
            {
              'anthropic': {
                'container': {'id': ''},
              },
            },
            {
              'anthropic': {
                'container': {'id': 42},
              },
            },
          ],
        ),
        isNull,
      );
    });

    test('步级 metadata 含自定义 key 时同步转发 container id', () {
      final result = forwardAnthropicContainerIdFromLastStep(
        <ProviderMetadata?>[
          {
            'anthropic': {
              'container': {'id': 'container_a'},
            },
            'my-anthropic': {
              'container': {'id': 'container_a'},
            },
          },
        ],
      );

      expect(result, {
        'anthropic': {
          'container': {'id': 'container_a'},
        },
        'my-anthropic': {
          'container': {'id': 'container_a'},
        },
      });
    });

    test('providerKey 显式传入时补挂自定义 key(步级 metadata 无该 key)', () {
      final result = forwardAnthropicContainerIdFromLastStep(
        <ProviderMetadata?>[
          {
            'anthropic': {
              'container': {'id': 'container_a'},
            },
          },
        ],
        providerKey: 'my-anthropic',
      );

      expect(result, {
        'anthropic': {
          'container': {'id': 'container_a'},
        },
        'my-anthropic': {
          'container': {'id': 'container_a'},
        },
      });
    });
  });
}
