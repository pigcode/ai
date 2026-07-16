import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Creates the Anthropic Messages API `text_editor_20241022` provider tool.
ProviderTool textEditor_20241022() {
  return const ProviderTool(
    id: 'anthropic.text_editor_20241022',
    name: 'str_replace_editor',
    args: <String, Object?>{},
  );
}

/// Creates the Anthropic Messages API `text_editor_20250124` provider tool.
ProviderTool textEditor_20250124() {
  return const ProviderTool(
    id: 'anthropic.text_editor_20250124',
    name: 'str_replace_editor',
    args: <String, Object?>{},
  );
}

/// Creates the Anthropic Messages API `text_editor_20250728` provider tool.
ProviderTool textEditor_20250728({int? maxCharacters}) {
  final args = <String, Object?>{
    'maxCharacters': maxCharacters,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.text_editor_20250728',
    name: 'str_replace_based_edit_tool',
    args: args,
  );
}
