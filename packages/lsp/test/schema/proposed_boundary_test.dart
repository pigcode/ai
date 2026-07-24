import 'dart:io';

import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:pigcode_ai_lsp/pigcode_ai_lsp_proposed.dart' as proposed;
import 'package:test/test.dart';

void main() {
  test('stable barrel does not re-export the proposed entrypoint', () {
    final stableBarrel = File.fromUri(
      _packageRoot.resolve('lib/pigcode_ai_lsp.dart'),
    ).readAsStringSync();
    expect(stableBarrel, isNot(contains('pigcode_ai_lsp_proposed.dart')));
    expect(lspDefinitionClassifications.values, isNotEmpty);
    expect(proposed.lspProposedDefinitionNames, isEmpty);
  });
}

Uri get _packageRoot {
  final current = Directory.current.absolute.uri;
  return File.fromUri(current.resolve('pubspec.yaml')).existsSync() &&
          current.pathSegments.where((segment) => segment.isNotEmpty).last ==
              'lsp'
      ? current
      : current.resolve('packages/lsp/');
}
