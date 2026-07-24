import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('tracks work-done and partial tokens independently', () {
    final progress = LspProgressRegistry(connectionId: 3);
    progress
      ..beginWorkDone('work', title: 'Indexing')
      ..reportWorkDone('work', message: 'Half', percentage: 50)
      ..registerPartial('partial', requestId: 8)
      ..addPartial('partial', const <Object?>[1])
      ..addPartial('partial', const <Object?>[2])
      ..endWorkDone('work', message: 'Done');

    expect(progress.workDone('work').ended, isTrue);
    expect(progress.partial('partial').values, const [
      <Object?>[1],
      <Object?>[2],
    ]);
  });

  test('rejects duplicate, unknown, and already-ended tokens', () {
    final progress = LspProgressRegistry(connectionId: 3)
      ..beginWorkDone(1, title: 'Build');
    expect(
      () => progress.beginWorkDone(1, title: 'Again'),
      throwsA(isA<LspProgressException>()),
    );
    expect(
      () => progress.addPartial('unknown', const {}),
      throwsA(isA<LspProgressException>()),
    );
    progress.endWorkDone(1);
    expect(
      () => progress.reportWorkDone(1, message: 'late'),
      throwsA(isA<LspProgressException>()),
    );
  });
}
