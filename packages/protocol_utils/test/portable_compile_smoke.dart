import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';

void main() {
  if (protocolUtilitiesApiVersion != 1) {
    throw StateError('Unexpected protocol utilities API version.');
  }
}
