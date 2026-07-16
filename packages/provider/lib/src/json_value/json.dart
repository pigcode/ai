import 'package:equatable/equatable.dart';

/// 任意合法的 JSON 值:`null` / `bool` / `num` / `String` /
/// [JsonObject] / [JsonArray]。契约层只承载,不在此层做结构校验。
typedef JsonValue = Object?;

/// JSON 对象:键为字符串,值为任意 [JsonValue]。
typedef JsonObject = Map<String, Object?>;

/// JSON 数组:元素为任意 [JsonValue]。
typedef JsonArray = List<Object?>;

/// JSON Schema(Draft-07 文档)的薄封装:契约层只承载 [value],不校验。
///
/// 使用 [EquatableMixin] 做值相等:[props] 只含 [value],equatable 会
/// 对其中的 [JsonObject](含嵌套 Map/List)做深比较,故两个包裹结构相等
/// 嵌套映射的 [JsonSchema] 判为相等。
final class JsonSchema with EquatableMixin {
  /// 用给定的 JSON Schema 文档 [value] 构造一个薄封装。
  const JsonSchema(this.value);

  /// 被封装的 JSON Schema 文档。
  final JsonObject value;

  @override
  List<Object?> get props => [value];
}
