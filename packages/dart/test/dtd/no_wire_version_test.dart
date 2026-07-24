import 'dart:io';

import 'package:pigcode_ai_dart/pigcode_ai_dart_dtd.dart';
import 'package:test/test.dart';

void main() {
  test('DTD availability is inventory-only and has no wire version', () {
    expect(
      dtdInventoryPolicy.accepts('dtd-fixed-inventory-v1'),
      isTrue,
    );
    final packagePath = File('lib/src/dtd/generated/inventory.g.dart');
    final generated = (packagePath.existsSync()
            ? packagePath
            : File(
                'packages/dart/lib/src/dtd/generated/inventory.g.dart',
              ))
        .readAsStringSync();
    expect(generated, isNot(contains('wireVersion')));
    expect(generated, isNot(contains('minimumVersion')));
    expect(generated, isNot(contains('maximumVersion')));
  });
}
