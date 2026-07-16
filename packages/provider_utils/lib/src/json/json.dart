import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';
import 'package:equatable/equatable.dart';
import 'package:json_schema/json_schema.dart' as js;

/// JSON 解析(及后续任务补充的结构校验)的统一结果类型。
///
/// 判别联合:成功为 [ParseSuccess],失败为 [ParseFailure]。[T] 为成功时
/// 承载的值类型;[rawValue] 始终保留转换前的原始值(v7 语义),便于调用方
/// 在结构校验发生类型转换后仍能拿到原始 JSON 值用于日志或降级处理。
sealed class ParseResult<T> {
  /// 常量基构造器,供 [ParseSuccess]/[ParseFailure] `const` 构造。
  const ParseResult();
}

/// 解析(及可选的结构校验)成功。
final class ParseSuccess<T> extends ParseResult<T> with EquatableMixin {
  /// 用给定的 [value] 与可选的转换前原始值 [rawValue] 构造一个成功结果。
  const ParseSuccess(this.value, {this.rawValue});

  /// 解析(及校验)后的值。
  final T value;

  /// 转换前原始值(v7 语义)。
  final Object? rawValue;

  @override
  List<Object?> get props => [value, rawValue];
}

/// 解析或结构校验失败。
final class ParseFailure<T> extends ParseResult<T> with EquatableMixin {
  /// 用给定的 [error] 与可选的转换前原始值 [rawValue] 构造一个失败结果。
  const ParseFailure(this.error, {this.rawValue});

  /// 失败原因:JSON 语法错误为 [JsonParseError],结构校验失败为
  /// `TypeValidationError`(见 Task 2)。
  final AiError error;

  /// 转换前原始值(v7 语义);语法解析阶段失败时通常为 `null`。
  final Object? rawValue;

  @override
  List<Object?> get props => [error, rawValue];
}

/// 将 [text] 解析为 [JsonValue]。
///
/// 语法不合法时抛出 [JsonParseError](携带原始 [text] 与底层
/// [FormatException] 作为 [AiError.cause])。若 [text] 恰好是某个已构造好的
/// [JsonParseError] 的诱因,本函数不做二次包装判断——那一层去重发生在
/// 调用方(如 Task 2 的结构校验)组合本函数与 [validateTypes] 时。
JsonValue parseJson(String text) {
  try {
    return jsonDecode(text) as JsonValue;
  } on FormatException catch (error) {
    throw JsonParseError(text: text, cause: error);
  }
}

/// [parseJson] 的不抛异常版本。
///
/// 语法合法时返回 [ParseSuccess],`rawValue` 与 `value` 相同(无结构校验、
/// 无类型转换发生);语法不合法时返回 [ParseFailure],[ParseFailure.error]
/// 恒为 [JsonParseError],`rawValue` 为 `null`(解析阶段失败,没有可回填的
/// 原始值)。
ParseResult<JsonValue> safeParseJson(String text) {
  try {
    final value = jsonDecode(text) as JsonValue;
    return ParseSuccess<JsonValue>(value, rawValue: value);
  } on FormatException catch (error) {
    return ParseFailure<JsonValue>(
      JsonParseError(text: text, cause: error),
    );
  }
}

/// JSON Schema 结构校验的统一结果类型。
///
/// 判别联合:通过为 [ValidationSuccess],不通过为 [ValidationFailure]。
sealed class ValidationResult {
  /// 常量基构造器,供 [ValidationSuccess]/[ValidationFailure] `const` 构造。
  const ValidationResult();
}

/// 结构校验通过。
final class ValidationSuccess extends ValidationResult with EquatableMixin {
  /// 用通过校验的 [value] 构造一个成功结果。
  const ValidationSuccess(this.value);

  /// 通过校验的值(诊断/回显用,类型不定)。
  final Object? value;

  @override
  List<Object?> get props => [value];
}

/// 结构校验未通过。
final class ValidationFailure extends ValidationResult with EquatableMixin {
  /// 用校验失败的 [error] 构造一个失败结果。
  const ValidationFailure(this.error);

  /// 校验失败的具体原因,携带原值与库产出的违规明细文本。
  final TypeValidationError error;

  @override
  List<Object?> get props => [error];
}

/// 基于契约 [JsonSchema] 构造的 JSON Schema 校验器。
///
/// 校验委托给 `package:json_schema`(不手写校验器);构造时一次性调用
/// [js.JsonSchema.create] 完成 schema 编译并缓存,`validate` 可对多个实例
/// 重复调用而不重新编译 schema。
final class JsonSchemaValidator {
  /// 用契约层 [schema] 构造校验器;内部立即编译一次 `js.JsonSchema`。
  JsonSchemaValidator.fromContract(JsonSchema schema)
      : _schema = js.JsonSchema.create(schema.value);

  final js.JsonSchema _schema;

  /// 用本校验器校验 [value] 的结构。
  ///
  /// 通过时返回 [ValidationSuccess]([ValidationSuccess.value] 即传入的
  /// [value],`json_schema` 库不做类型转换/coercion);不通过时返回
  /// [ValidationFailure],其 [TypeValidationError.value] 为 [value]、
  /// [TypeValidationError.cause] 为库产出的违规明细文本(每条错误一行,
  /// 便于日志排查)。
  ValidationResult validate(Object? value) {
    final results = _schema.validate(value);
    if (results.isValid) {
      return ValidationSuccess(value);
    }
    final details = results.errors.map((error) => error.toString()).join('\n');
    return ValidationFailure(
      TypeValidationError(value: value, cause: details),
    );
  }
}

/// 用 [validator] 校验 [value]。
///
/// 通过时返回校验后的值(即 [value] 本身,见 [JsonSchemaValidator.validate]
/// 的说明);不通过时抛出 [TypeValidationError]。
Object? validateTypes(Object? value, JsonSchemaValidator validator) {
  final result = safeValidateTypes(value, validator);
  return switch (result) {
    ValidationSuccess(:final value) => value,
    ValidationFailure(:final error) => throw error,
  };
}

/// [validateTypes] 的不抛异常版本,直接返回 [ValidationResult]。
ValidationResult safeValidateTypes(
    Object? value, JsonSchemaValidator validator) {
  return validator.validate(value);
}
