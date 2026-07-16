import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// Creates the Anthropic Messages API `code_execution_20250522` provider
/// tool.
ProviderTool codeExecution_20250522() {
  return const ProviderTool(
    id: 'anthropic.code_execution_20250522',
    name: 'code_execution',
    args: <String, Object?>{},
  );
}

/// Creates the Anthropic Messages API `code_execution_20250825` provider
/// tool.
ProviderTool codeExecution_20250825() {
  return const ProviderTool(
    id: 'anthropic.code_execution_20250825',
    name: 'code_execution',
    args: <String, Object?>{},
    // provider 工具自动续接标注(:274):programmatic tool calling 下
    // code_execution 触发 client 工具时,其结果可能延后到下一轮。
    supportsDeferredResults: true,
  );
}

/// Creates the Anthropic Messages API `code_execution_20260120` provider
/// tool.
ProviderTool codeExecution_20260120() {
  return const ProviderTool(
    id: 'anthropic.code_execution_20260120',
    name: 'code_execution',
    args: <String, Object?>{},
    // provider 工具自动续接标注(:308)。
    supportsDeferredResults: true,
  );
}
