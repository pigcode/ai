import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('open values preserve known and future strings without loss', () {
    final known = DapOpenValue<String>(
      'breakpoint',
      knownValues: const {'breakpoint', 'exception'},
    );
    final future = DapOpenValue<String>(
      'future-reason',
      knownValues: const {'breakpoint', 'exception'},
    );

    expect(known.isKnown, isTrue);
    expect(future.isKnown, isFalse);
    expect(future.toJson(), 'future-reason');
    expect(
      DapCodec.instance
          .decode(
            '{"seq":1,"type":"event","event":"stopped",'
            '"body":{"reason":"future-reason","threadId":1}}',
          )
          .toJson()['body'],
      containsPair('reason', 'future-reason'),
    );
  });
}
