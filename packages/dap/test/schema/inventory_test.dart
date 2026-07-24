import 'package:pigcode_ai_dap/pigcode_ai_dap.dart';
import 'package:test/test.dart';

void main() {
  test('classifies every definition, request, event, and enum occurrence', () {
    expect(dapDefinitionClassifications, hasLength(192));
    expect(dapRequestDescriptors, hasLength(45));
    expect(dapEventDescriptors, hasLength(17));
    expect(
      dapDefinitionClassifications.values.where(
        (classification) => classification == 'arguments',
      ),
      hasLength(44),
    );
    expect(dapClosedEnumCount, 83);
    expect(dapOpenEnumCount, 14);
    expect(dapRequestsByCommand, hasLength(45));
    expect(dapEventsByName, hasLength(17));
  });
}
