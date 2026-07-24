import 'package:pigcode_ai_dart/pigcode_ai_dart_analysis_server.dart';
import 'package:test/test.dart';

void main() {
  test('parses SourceChange into immutable typed edits', () {
    final proposal = AnalysisServerSourceChangeProposal.fromJson(
      const <String, Object?>{
        'message': 'Rename symbol',
        'edits': <Object?>[
          <String, Object?>{
            'file': '/workspace/main.dart',
            'fileStamp': 7,
            'edits': <Object?>[
              <String, Object?>{
                'offset': 4,
                'length': 3,
                'replacement': 'renamed',
                'description': 'Update reference',
              },
            ],
          },
        ],
        'linkedEditGroups': <Object?>[],
        'selection': <String, Object?>{
          'file': '/workspace/main.dart',
          'offset': 11,
        },
        'selectionLength': 0,
      },
    );

    expect(proposal.message, 'Rename symbol');
    expect(proposal.edits.single.fileStamp, 7);
    expect(proposal.edits.single.edits.single.replacement, 'renamed');
    expect(proposal.selection?.offset, 11);
    expect(
      () => proposal.toJson()['message'] = 'mutated',
      throwsUnsupportedError,
    );
  });

  test('capability never authorizes an edit without a caller handler', () {
    final connection = AnalysisServerConnection();
    final version = connection.beginVersionQuery();
    connection.completeVersionQuery(
      version.id,
      const <String, Object?>{'version': '1.40.1'},
      clientCapabilities: const <String, Object?>{
        'requests': <Object?>['server.showMessageRequest'],
        'supportsUris': true,
      },
    );
    expect(connection.capabilities.supportsRequest('edit.getFixes'), isTrue);

    final dispatcher = AnalysisServerEditProposalDispatcher();
    var handled = false;
    expect(
      () => dispatcher.dispatchSourceChange(
        const <String, Object?>{
          'message': 'Change',
          'edits': <Object?>[],
          'linkedEditGroups': <Object?>[],
        },
      ),
      throwsA(
        isA<ToolingProposalError>().having(
          (error) => error.code,
          'code',
          'analysis_server_edit_handler_missing',
        ),
      ),
    );
    expect(handled, isFalse);

    dispatcher.register((proposal) {
      handled = true;
      return const <String, Object?>{'accepted': true};
    });
    expect(
      dispatcher.dispatchSourceChange(
        const <String, Object?>{
          'message': 'Change',
          'edits': <Object?>[],
          'linkedEditGroups': <Object?>[],
        },
      ),
      const <String, Object?>{'accepted': true},
    );
    expect(handled, isTrue);
  });

  test('rejects malformed and unbounded edit proposals', () {
    expect(
      () => AnalysisServerSourceChangeProposal.fromJson(
        const <String, Object?>{
          'message': 'Bad',
          'edits': <Object?>[
            <String, Object?>{
              'file': '/workspace/main.dart',
              'fileStamp': 0,
              'edits': <Object?>[
                <String, Object?>{
                  'offset': -1,
                  'length': 0,
                  'replacement': '',
                },
              ],
            },
          ],
          'linkedEditGroups': <Object?>[],
        },
      ),
      throwsA(isA<ToolingProposalError>()),
    );
  });
}
