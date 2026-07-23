import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  test('portable barrel exposes the protocol utilities API version', () {
    expect(protocolUtilitiesApiVersion, 1);
  });
}
