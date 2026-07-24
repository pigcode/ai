import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('preserves versioned edits, resource operations, and annotations', () {
    const params = <String, Object?>{
      'label': 'Refactor',
      'edit': <String, Object?>{
        'documentChanges': <Object?>[
          <String, Object?>{
            'textDocument': <String, Object?>{
              'uri': 'file:///a.dart',
              'version': 3,
            },
            'edits': <Object?>[
              <String, Object?>{
                'range': <String, Object?>{
                  'start': <String, Object?>{'line': 0, 'character': 0},
                  'end': <String, Object?>{'line': 0, 'character': 0},
                },
                'newText': 'final ',
                'annotationId': 'change-1',
              },
            ],
          },
          <String, Object?>{
            'kind': 'create',
            'uri': 'file:///new.dart',
            'annotationId': 'change-1',
          },
        ],
        'changeAnnotations': <String, Object?>{
          'change-1': <String, Object?>{
            'label': 'Create and edit',
            'needsConfirmation': true,
          },
        },
      },
    };

    final proposal = LspApplyEditProposal.fromParams(params);
    expect(proposal.label, 'Refactor');
    expect(proposal.documentChanges, hasLength(2));
    expect(
      proposal.documentChanges.first['textDocument'],
      const {'uri': 'file:///a.dart', 'version': 3},
    );
    expect(proposal.documentChanges.last['kind'], 'create');
    expect(proposal.changeAnnotations.keys, const ['change-1']);
    expect(proposal.toJson(), params);
  });
}
