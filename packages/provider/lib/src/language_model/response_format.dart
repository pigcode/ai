import 'package:equatable/equatable.dart';

import '../json_value/json.dart';

/// 响应格式约束(判别联合):纯文本 或 结构化 JSON。
sealed class ResponseFormat extends Equatable {
  const ResponseFormat();
}

/// 不加结构约束的纯文本响应。
final class ResponseFormatText extends ResponseFormat {
  const ResponseFormatText();

  @override
  List<Object?> get props => const <Object?>[];
}

/// 结构化 JSON 响应:可选 schema / 名称 / 描述。
final class ResponseFormatJson extends ResponseFormat {
  const ResponseFormatJson({this.schema, this.name, this.description});

  /// 期望输出所遵循的 JSON Schema(契约层只承载,不校验)。
  final JsonSchema? schema;

  /// 结构的可读名称(部分 provider 需要)。
  final String? name;

  /// 结构的可读描述(部分 provider 需要)。
  final String? description;

  @override
  List<Object?> get props => <Object?>[schema, name, description];
}
