import 'dart:io';

import 'package:pigcode_ai_agent_io/pigcode_ai_agent_io.dart';
import 'package:pigcode_ai_agent_kernel/pigcode_ai_agent_kernel.dart';
import 'package:test/test.dart';

void main() {
  late Directory temporary;
  late Directory root;
  late StoreLayout layout;

  setUp(() {
    temporary = Directory.systemTemp.createTempSync('store-path-security-');
    root = Directory.fromUri(temporary.uri.resolve('store/'))..createSync();
    layout = StoreLayout.open(root);
  });

  tearDown(() => temporary.deleteSync(recursive: true));

  test('P3-TM-ELEV-04 typed IDs cannot inject path traversal', () {
    expect(() => SessionId.parse('ses_../../outside'), throwsFormatException);
    expect(
      () => SnapshotId.parse('snp_%2foutside'),
      throwsFormatException,
    );
    expect(
      layout
          .sessionDirectory(
            SessionId.parse('ses_00000000000000000000000000000000'),
          )
          .path,
      startsWith(layout.root.path),
    );
  });

  test('P3-TM-ELEV-05 generated artifacts stay inside the root', () {
    final sessionId = SessionId.parse('ses_00000000000000000000000000000000');
    final file = layout.journalSegmentFile(
      sessionId,
      startSequence: 1,
      digest: ''.padLeft(64, 'a'),
    );
    expect(file.absolute.path, startsWith(layout.root.absolute.path));

    final outside = File.fromUri(temporary.uri.resolve('outside.pigj'))
      ..writeAsBytesSync(const <int>[1]);
    expect(
      () => layout.validateExistingArtifact(outside),
      throwsA(
        isA<StoreLayoutException>().having(
          (error) => error.code,
          'code',
          StoreLayoutErrorCode.outsideRoot,
        ),
      ),
    );
  });
}
