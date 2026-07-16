import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;

import 'fix_json.dart';

enum PartialJsonState {
  undefinedInput,
  successfulParse,
  repairedParse,
  failedParse,
}

final class PartialJsonResult {
  const PartialJsonResult({required this.value, required this.state});

  /// Parsed JSON value; `null` when [state] is failedParse or undefinedInput.
  final provider.JsonValue value;
  final PartialJsonState state;
}

PartialJsonResult parsePartialJson(String? text) {
  if (text == null) {
    return const PartialJsonResult(
      value: null,
      state: PartialJsonState.undefinedInput,
    );
  }

  final parsed = utils.safeParseJson(text);
  if (parsed is utils.ParseSuccess<provider.JsonValue>) {
    return PartialJsonResult(
      value: parsed.value,
      state: PartialJsonState.successfulParse,
    );
  }

  final repairedText = fixJson(text);
  final repaired = utils.safeParseJson(repairedText);
  if (repaired is utils.ParseSuccess<provider.JsonValue>) {
    return PartialJsonResult(
      value: repaired.value,
      state: PartialJsonState.repairedParse,
    );
  }

  return const PartialJsonResult(
    value: null,
    state: PartialJsonState.failedParse,
  );
}
