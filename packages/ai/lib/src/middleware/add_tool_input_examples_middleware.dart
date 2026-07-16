import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// 将工具入参示例序列化并追加到函数工具描述中的 formatter。
typedef ToolInputExampleFormatter = String Function(
  provider.JsonObject example,
  int index,
);

/// 把 [provider.FunctionTool.inputExamples] 追加进工具描述的中间件。
///
/// 这对不原生支持 `inputExamples` 的 provider 有用。默认会把示例转成紧凑
/// JSON 并移除原字段,避免 provider 同时收到文字版与结构化版示例。
provider.LanguageModelMiddleware addToolInputExamplesMiddleware({
  String prefix = 'Input Examples:',
  ToolInputExampleFormatter format = _defaultToolInputExampleFormatter,
  bool remove = true,
}) {
  return provider.LanguageModelMiddleware(
    transformParams: ({
      required bool stream,
      required provider.LanguageModelCallOptions params,
      required provider.LanguageModel model,
    }) async {
      final tools = params.tools;
      if (tools == null || tools.isEmpty) {
        return params;
      }

      return params.copyWith(
        tools: [
          for (final tool in tools)
            if (tool is provider.FunctionTool &&
                tool.inputExamples != null &&
                tool.inputExamples!.isNotEmpty)
              _withExamplesInDescription(
                tool,
                prefix: prefix,
                format: format,
                remove: remove,
              )
            else
              tool,
        ],
      );
    },
  );
}

provider.FunctionTool _withExamplesInDescription(
  provider.FunctionTool tool, {
  required String prefix,
  required ToolInputExampleFormatter format,
  required bool remove,
}) {
  final formattedExamples = <String>[
    for (final MapEntry(:key, :value) in tool.inputExamples!.asMap().entries)
      format(value, key),
  ].join('\n');
  final examplesSection = '$prefix\n$formattedExamples';
  final description = tool.description == null
      ? examplesSection
      : '${tool.description}\n\n$examplesSection';

  return provider.FunctionTool(
    name: tool.name,
    description: description,
    inputSchema: tool.inputSchema,
    inputExamples: remove ? null : tool.inputExamples,
    strict: tool.strict,
    providerOptions: tool.providerOptions,
  );
}

String _defaultToolInputExampleFormatter(
  provider.JsonObject example,
  int index,
) {
  return jsonEncode(example);
}
