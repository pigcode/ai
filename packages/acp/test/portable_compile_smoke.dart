import 'package:pigcode_ai_acp/pigcode_ai_acp.dart';

void main() {
  if (acpProtocolVersion != 1 || acpSchemaSha256.length != 64) {
    throw StateError('Unexpected ACP source identity.');
  }
}
