import 'dart:convert';

/// Anthropic 受限解码支持的 string format 白名单(上游
/// sanitize-json-schema.ts:3-14,`SUPPORTED_STRING_FORMATS`)。
const Set<String> _supportedStringFormats = <String>{
  'date-time',
  'time',
  'date',
  'duration',
  'email',
  'hostname',
  'uri',
  'ipv4',
  'ipv6',
  'uuid',
};

/// 需要从 schema 中删除并降级为 description 文本的约束关键字
/// (上游 :16-31,`DESCRIPTION_CONSTRAINT_KEYS`,共 14 个)。
const List<String> _descriptionConstraintKeys = <String>[
  'minimum',
  'maximum',
  'exclusiveMinimum',
  'exclusiveMaximum',
  'multipleOf',
  'minLength',
  'maxLength',
  'pattern',
  'minItems',
  'maxItems',
  'uniqueItems',
  'minProperties',
  'maxProperties',
  'not',
];

/// 清洗发给 Anthropic `output_config.format.schema` 的 JSON Schema,
/// 移除 Anthropic 拒绝的关键字(对照上游 sanitize-json-schema.ts:54-166)。
///
/// 注意:这里只清洗发给受限解码器的**副本**;本地结果校验仍使用原
/// schema(调用点在 doGenerate 的结构化输出路径,见 Task 18)。
///
/// 白名单复制策略:
/// - `$ref` 存在时整个节点只保留 `{$ref}`,其余字段丢弃(:60-62);
/// - `$schema`/`$id`/`title`/`description`/`enum`/`type` 非 null 才复制;
///   `default`/`const` 用 containsKey 判断,可保留显式 null(:80-86);
/// - `oneOf` 改写为 `anyOf`(仅当无 anyOf 时,else-if,:98-100);
/// - `anyOf`/`allOf`/`definitions`/`$defs`/`properties`/`items` 递归清洗;
/// - object 节点(`type: 'object'` 或有 properties)强制输出
///   `additionalProperties: false` 并保留 `required`(:127-142);
/// - format 仅白名单内保留;白名单外与 14 个约束关键字一起降级为
///   description 文本(`'; '` 连接、末尾 `.`,:157-187);
/// - 其余关键字一律丢弃。
Map<String, Object?> sanitizeJsonSchema(Map<String, Object?> schema) =>
    _sanitizeSchema(schema);

/// 递归入口:boolean 子 schema 与其他非 Map 值原样返回(上游 :44-52)。
Object? _sanitizeDefinition(Object? definition) {
  if (definition is Map<String, Object?>) {
    return _sanitizeSchema(definition);
  }
  return definition;
}

Map<String, Object?> _sanitizeSchema(Map<String, Object?> schema) {
  // $ref 优先短路:节点上的 description/title/siblings 全部丢失(:60-62)。
  final ref = schema[r'$ref'];
  if (ref != null) {
    return <String, Object?>{r'$ref': ref};
  }

  final result = <String, Object?>{};

  // 非 null 才复制的白名单字段(:64-94)。
  for (final key in <String>[r'$schema', r'$id', 'title', 'description']) {
    final value = schema[key];
    if (value != null) {
      result[key] = value;
    }
  }

  // default/const 用 containsKey 对应上游 `!== undefined`,保留显式 null。
  for (final key in <String>['default', 'const']) {
    if (schema.containsKey(key)) {
      result[key] = schema[key];
    }
  }

  final enumValue = schema['enum'];
  if (enumValue != null) {
    result['enum'] = enumValue;
  }

  final type = schema['type'];
  if (type != null) {
    result['type'] = type;
  }

  // anyOf 优先;仅当无 anyOf 时才把 oneOf 改写为 anyOf(else-if,
  // 有意放宽互斥语义,:96-100)。
  final anyOf = schema['anyOf'];
  final oneOf = schema['oneOf'];
  if (anyOf is List<Object?>) {
    result['anyOf'] = anyOf.map(_sanitizeDefinition).toList();
  } else if (oneOf is List<Object?>) {
    result['anyOf'] = oneOf.map(_sanitizeDefinition).toList();
  }

  final allOf = schema['allOf'];
  if (allOf is List<Object?>) {
    result['allOf'] = allOf.map(_sanitizeDefinition).toList();
  }

  // definitions / $defs 逐项递归(:106-125)。
  for (final key in <String>['definitions', r'$defs']) {
    final value = schema[key];
    if (value is Map<String, Object?>) {
      result[key] = value.map(
        (name, definition) => MapEntry(name, _sanitizeDefinition(definition)),
      );
    }
  }

  // object 节点:强制 additionalProperties: false,required 仅在此分支
  // 保留(:127-142)。
  final properties = schema['properties'];
  if (type == 'object' || properties != null) {
    if (properties is Map<String, Object?>) {
      result['properties'] = properties.map(
        (name, definition) => MapEntry(name, _sanitizeDefinition(definition)),
      );
    }
    result['additionalProperties'] = false;
    final required = schema['required'];
    if (required != null) {
      result['required'] = required;
    }
  }

  // items:数组逐项递归,单个 schema 直接递归(:144-148)。
  final items = schema['items'];
  if (items != null) {
    result['items'] = items is List<Object?>
        ? items.map(_sanitizeDefinition).toList()
        : _sanitizeDefinition(items);
  }

  // format 仅白名单内保留(:150-155);白名单外在约束降级里进 description。
  final format = schema['format'];
  if (format is String && _supportedStringFormats.contains(format)) {
    result['format'] = format;
  }

  // 约束降级文本追加到 description:已有 description 时以换行拼接
  // (:157-163)。
  final constraintDescription = _constraintDescription(schema);
  if (constraintDescription != null) {
    final existing = result['description'];
    result['description'] = existing == null
        ? constraintDescription
        : '$existing\n$constraintDescription';
  }

  return result;
}

/// 生成约束降级文本(上游 getConstraintDescription,:166-187):
/// 值为 null 或 false 的约束无声丢弃;白名单外的 format 同列追加;
/// 多条以 `'; '` 连接,末尾统一加 `.`。
String? _constraintDescription(Map<String, Object?> schema) {
  final descriptions = <String>[];
  for (final key in _descriptionConstraintKeys) {
    final value = schema[key];
    if (value == null || value == false) {
      continue;
    }
    descriptions.add('${_constraintName(key)}: ${_constraintValue(value)}');
  }

  final format = schema['format'];
  if (format is String && !_supportedStringFormats.contains(format)) {
    descriptions.add('format: $format');
  }

  return descriptions.isEmpty ? null : '${descriptions.join('; ')}.';
}

/// camelCase → 空格小写(`minLength` → `min length`,上游 :189-191)。
String _constraintName(String key) => key.replaceAllMapped(
      RegExp('[A-Z]'),
      (match) => ' ${match[0]!.toLowerCase()}',
    );

/// string 值原样,其余 jsonEncode(上游 :193-199)。
String _constraintValue(Object value) =>
    value is String ? value : jsonEncode(value);
