import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('converts each privileged reverse request to a typed proposal', () {
    final proposals = <LspProposal>[];
    final dispatcher = LspProposalDispatcher();
    for (final method in const [
      'workspace/applyEdit',
      'workspace/configuration',
      'window/showDocument',
      'window/showMessageRequest',
      'client/registerCapability',
      'client/unregisterCapability',
    ]) {
      dispatcher.register(method, (proposal) {
        proposals.add(proposal);
        return null;
      });
    }

    dispatcher.dispatch(
      'workspace/applyEdit',
      const {
        'edit': <String, Object?>{'changes': <String, Object?>{}},
      },
    );
    dispatcher.dispatch(
      'workspace/configuration',
      const {'items': <Object?>[]},
    );
    dispatcher.dispatch(
      'window/showDocument',
      const {'uri': 'file:///a.dart'},
    );
    dispatcher.dispatch(
      'window/showMessageRequest',
      const {'type': 3, 'message': 'Choose'},
    );
    dispatcher.dispatch(
      'client/registerCapability',
      const {'registrations': <Object?>[]},
    );
    dispatcher.dispatch(
      'client/unregisterCapability',
      const {'unregisterations': <Object?>[]},
    );

    expect(proposals, hasLength(6));
    expect(proposals.first, isA<LspApplyEditProposal>());
    expect(proposals[1], isA<LspConfigurationProposal>());
    expect(proposals[2], isA<LspShowDocumentProposal>());
    expect(proposals[3], isA<LspShowMessageProposal>());
    expect(proposals[4], isA<LspRegistrationProposal>());
    expect(proposals[5], isA<LspUnregistrationProposal>());
  });

  test('never handles a reverse request without a caller handler', () {
    final dispatcher = LspProposalDispatcher();
    expect(
      () => dispatcher.dispatch(
        'workspace/applyEdit',
        const {
          'edit': <String, Object?>{'changes': <String, Object?>{}},
        },
      ),
      throwsA(isA<LspProposalException>()),
    );
  });
}
