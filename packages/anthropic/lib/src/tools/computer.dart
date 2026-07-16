import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Creates the Anthropic Messages API `computer_20241022` provider tool.
ProviderTool computer_20241022({
  required int displayWidthPx,
  required int displayHeightPx,
  int? displayNumber,
}) {
  final args = <String, Object?>{
    'displayWidthPx': displayWidthPx,
    'displayHeightPx': displayHeightPx,
    'displayNumber': displayNumber,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.computer_20241022',
    name: 'computer',
    args: args,
  );
}

/// Creates the Anthropic Messages API `computer_20250124` provider tool.
ProviderTool computer_20250124({
  required int displayWidthPx,
  required int displayHeightPx,
  int? displayNumber,
}) {
  final args = <String, Object?>{
    'displayWidthPx': displayWidthPx,
    'displayHeightPx': displayHeightPx,
    'displayNumber': displayNumber,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.computer_20250124',
    name: 'computer',
    args: args,
  );
}

/// Creates the Anthropic Messages API `computer_20251124` provider tool.
ProviderTool computer_20251124({
  required int displayWidthPx,
  required int displayHeightPx,
  int? displayNumber,
  bool? enableZoom,
}) {
  final args = <String, Object?>{
    'displayWidthPx': displayWidthPx,
    'displayHeightPx': displayHeightPx,
    'displayNumber': displayNumber,
    'enableZoom': enableZoom,
  }..removeWhere((_, value) => value == null);

  return ProviderTool(
    id: 'anthropic.computer_20251124',
    name: 'computer',
    args: args,
  );
}
