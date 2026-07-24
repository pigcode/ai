import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('tracks ordered progress start, update, and end', () {
    final progress = DapProgressRegistry()
      ..start(progressId: 'build', title: 'Build', requestId: 3)
      ..update(progressId: 'build', message: 'Half', percentage: 50)
      ..end(progressId: 'build', message: 'Done');

    final state = progress.progress('build');
    expect(state.ended, isTrue);
    expect(state.percentage, 50);
    expect(state.requestId, 3);
  });

  test('rejects duplicate, unknown, and late progress', () {
    final progress = DapProgressRegistry()
      ..start(progressId: 'build', title: 'Build');
    expect(
      () => progress.start(progressId: 'build', title: 'Again'),
      throwsA(isA<DapProgressException>()),
    );
    expect(
      () => progress.update(progressId: 'unknown'),
      throwsA(isA<DapProgressException>()),
    );
    progress.end(progressId: 'build');
    expect(
      () => progress.update(progressId: 'build'),
      throwsA(isA<DapProgressException>()),
    );
  });
}
