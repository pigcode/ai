import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('cancel intent permits partial data then a late success', () {
    final cancellations = LspCancellationRegistry(connectionId: 5)
      ..track(requestId: 1, method: 'textDocument/completion');

    final message = cancellations.requestCancel(1);
    expect(message, const {
      'jsonrpc': '2.0',
      'method': r'$/cancelRequest',
      'params': {'id': 1},
    });
    cancellations.addPartial(1, const <Object?>['first']);
    final completion = cancellations.completeSuccess(1, const {'items': []});

    expect(completion.cancelRequested, isTrue);
    expect(completion.lateAfterCancel, isTrue);
    expect(completion.partialValues, const [
      <Object?>['first'],
    ]);
    expect(completion.result, const {'items': <Object?>[]});
    expect(
      () => cancellations.completeError(1, code: -32800, message: 'cancelled'),
      throwsA(
        isA<LspCancellationException>().having(
          (error) => error.code,
          'code',
          'lsp_response_tombstoned',
        ),
      ),
    );
  });

  test('records a cancellation error and rejects unknown/duplicate cancel', () {
    final cancellations = LspCancellationRegistry(connectionId: 5)
      ..track(requestId: 2, method: 'textDocument/hover');
    cancellations.requestCancel(2);
    expect(
      () => cancellations.requestCancel(2),
      throwsA(isA<LspCancellationException>()),
    );
    final completion = cancellations.completeError(
      2,
      code: -32800,
      message: 'Request cancelled',
    );
    expect(completion.remoteErrorCode, -32800);
    expect(
      () => cancellations.requestCancel(99),
      throwsA(isA<LspCancellationException>()),
    );
  });
}
