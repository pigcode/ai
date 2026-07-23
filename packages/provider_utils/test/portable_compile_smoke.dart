import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart';

void main() {
  final surface = <Object?>[
    withoutTrailingSlash('https://example.invalid/v1/'),
    safeParseJson('{"portable":true}'),
    createIdGenerator(prefix: 'portable'),
  ];
  if (surface.length != 3) {
    throw StateError('provider_utils portable surface is incomplete');
  }
}
