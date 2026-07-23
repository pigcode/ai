import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';
import 'package:test/test.dart';

void main() {
  test('classifies every stable definition and method exactly once', () {
    expect(AcpSchema.instance.definitionNames, hasLength(142));
    expect(acpMethodDescriptors, hasLength(23));
    expect(acpMethodDescriptors.map((descriptor) => descriptor.method).toSet(),
        hasLength(23));
    expect(
      acpMessageRoots,
      <String>{'Agent', 'Client', 'ProtocolLevel'},
    );
    expect(
      acpDefinitionClassifications.keys.toSet(),
      AcpSchema.instance.definitionNames,
    );
    expect(
      acpDefinitionClassifications.values,
      everyElement(anyOf('typed', 'validated-extension')),
    );
    expect(
      acpMethodDescriptors
          .singleWhere((descriptor) => descriptor.method == 'initialize')
          .requestDefinition,
      'InitializeRequest',
    );
    expect(
      acpMethodDescriptors
          .singleWhere(
            (descriptor) => descriptor.method == r'$/cancel_request',
          )
          .notificationDefinition,
      'CancelRequestNotification',
    );
  });
}
