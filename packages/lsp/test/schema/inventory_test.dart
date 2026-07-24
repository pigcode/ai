import 'package:pigcode_ai_lsp/pigcode_ai_lsp.dart';
import 'package:test/test.dart';

void main() {
  test('classifies every method and named model', () {
    expect(lspMethodDescriptors, hasLength(95));
    expect(
      lspMethodDescriptors.where(
        (descriptor) => descriptor.kind == LspMethodKind.request,
      ),
      hasLength(69),
    );
    expect(
      lspMethodDescriptors.where(
        (descriptor) => descriptor.kind == LspMethodKind.notification,
      ),
      hasLength(26),
    );
    expect(lspDefinitionClassifications, hasLength(450));
    expect(
      lspDefinitionClassifications.values,
      everyElement(anyOf('stable', 'proposed')),
    );
    expect(lspMethodsByName.keys.toSet(), {
      for (final descriptor in lspMethodDescriptors) descriptor.method,
    });
  });
}
