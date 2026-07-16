import 'dart:convert';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 单次工具调用的可变累积状态（内部使用，不对外暴露）。
class _TrackedToolCall {
  _TrackedToolCall({required this.id, required this.name});

  final String id;
  final String name;
  final StringBuffer arguments = StringBuffer();
  bool hasFinished = false;
}

/// 探测字符串是否可被解析为合法 JSON（对齐上游 `isParsableJson`：仅探测
/// 语法可解析性，不关心解析结果的形状；上游额外做的 prototype-pollution
/// 过滤是 JS 生态特有的安全考量——Dart `Map` 无原型链，此处不移植，属于
/// 设计文档明确的永久裁掉项）。
bool _isParsableJson(String input) {
  try {
    jsonDecode(input);
    return true;
  } catch (_) {
    return false;
  }
}

/// 判断累积的 arguments 是否可以安全地做“可解析即定稿”的提前探测。
///
/// 数学依据：在 append-only 的分片流下，只有 JSON 对象（`{...}`）和数组
/// （`[...]`）具备“可解析 ⇒ 已完整”的性质——因为再往一个已合法闭合的对象
/// /数组末尾追加任意非空白字符，结果必然不再是合法 JSON（要么在闭合括号
/// 后出现多余字符，要么破坏了原本的顶层结构）。但数字标量不具备这个性质：
/// `'1'` 已可解析为合法 JSON（数字 1），继续追加 `'23'` 后 `'123'` 仍是
/// 合法 JSON（数字 123）——可解析后仍可能继续增长，提前定稿会把尚未接收
/// 完整的标量参数腐坏成半截值。字符串/布尔/`null` 前缀同理不具备该保证
/// （如 `'"a"'` 后追加内容也可能仍保持合法但语义已变，`'null'` 理论上不会
/// 再增长但为一致性一并纳入排除范围），因此这里统一只放行对象/数组前缀。
///
/// 上游 `StreamingToolCallTracker` 每个 delta 后探测时没有这层防护，是
/// 因为 OpenAI 官方 API 的 `arguments` 现实中恒为 JSON 对象，标量场景不会
/// 出现；本实现面向泛 openai-compatible 方言，需要补上这层防护。对象/
/// 数组场景的提前定稿时序与上游完全一致，不受此 guard 影响。
bool _canProbeEarlyFinish(String accumulated) {
  final trimmed = accumulated.trimLeft();
  if (trimmed.isEmpty) {
    return false;
  }
  final firstChar = trimmed[0];
  return firstChar == '{' || firstChar == '[';
}

/// 按分片 `index` 聚合 OpenAI 风格的流式工具调用增量，事件产出式。
///
/// 语义对齐上游 `StreamingToolCallTracker`：[addDelta] 处理每个分片，
/// 在新 `index` 首次出现时立即产出 [ToolInputStart]；此后每次携带
/// `argumentsDelta` 产出 [ToolInputDelta]；每次分片处理后都会用与上游
/// `isParsableJson` 等价的语义探测累积的 arguments 是否已可解析为 JSON——
/// 一旦可解析（含首片已是完整 JSON 的情形），立即追加 [ToolInputEnd] +
/// [ToolCall] 并将该调用标记为已完成。已完成的调用若再收到同 `index` 的
/// 分片，按上游语义直接忽略（不重开、不再产出事件）。
///
/// Dart 化差异仅在事件的传递方式：不注入 `controller`，而是把本次分片
/// 应发出的事件作为返回值交给调用方（未来的 provider `doStream`）转发。
final class StreamingToolCallTracker {
  final Map<int, _TrackedToolCall> _calls = <int, _TrackedToolCall>{};
  int _nextIndex = 0;

  /// 处理一个 OpenAI 风格 tool-call 增量分片，返回应立即发出的契约流事件。
  ///
  /// [index] 缺省时退化为内部顺序计数（与上游 `toolCalls.length` 等价）。
  /// 新 `index` 首次出现时，[id] 与 [name] 均不能为空，否则抛
  /// [InvalidResponseDataError]（对齐上游对 `id`/`function.name` 缺失的
  /// 校验）。已完成的调用忽略后续分片（返回空列表）。
  List<LanguageModelStreamPart> addDelta({
    int? index,
    String? id,
    String? name,
    String? argumentsDelta,
  }) {
    final resolvedIndex = index ?? _nextIndex;

    final existing = _calls[resolvedIndex];
    if (existing == null) {
      return _startNewCall(
        resolvedIndex,
        id: id,
        name: name,
        argumentsDelta: argumentsDelta,
      );
    }

    return _continueCall(existing, argumentsDelta: argumentsDelta);
  }

  List<LanguageModelStreamPart> _startNewCall(
    int index, {
    required String? id,
    required String? name,
    required String? argumentsDelta,
  }) {
    if (id == null) {
      throw InvalidResponseDataError(
        data: {'index': index, 'id': id, 'name': name},
        message: "Expected 'id' to be a string.",
      );
    }
    if (name == null) {
      throw InvalidResponseDataError(
        data: {'index': index, 'id': id, 'name': name},
        message: "Expected 'function.name' to be a string.",
      );
    }

    final call = _TrackedToolCall(id: id, name: name);
    _calls[index] = call;
    if (index >= _nextIndex) {
      _nextIndex = index + 1;
    }

    final events = <LanguageModelStreamPart>[
      ToolInputStart(id: call.id, toolName: call.name),
    ];

    if (argumentsDelta != null) {
      call.arguments.write(argumentsDelta);
    }
    if (call.arguments.isNotEmpty) {
      events.add(ToolInputDelta(call.id, call.arguments.toString()));
    }

    final accumulated = call.arguments.toString();
    if (_canProbeEarlyFinish(accumulated) && _isParsableJson(accumulated)) {
      events.addAll(_finishCall(call));
    }

    return events;
  }

  List<LanguageModelStreamPart> _continueCall(
    _TrackedToolCall call, {
    required String? argumentsDelta,
  }) {
    if (call.hasFinished) {
      return const <LanguageModelStreamPart>[];
    }

    final events = <LanguageModelStreamPart>[];

    if (argumentsDelta != null) {
      call.arguments.write(argumentsDelta);
      events.add(ToolInputDelta(call.id, argumentsDelta));
    }

    final accumulated = call.arguments.toString();
    if (_canProbeEarlyFinish(accumulated) && _isParsableJson(accumulated)) {
      events.addAll(_finishCall(call));
    }

    return events;
  }

  List<LanguageModelStreamPart> _finishCall(_TrackedToolCall call) {
    call.hasFinished = true;
    return <LanguageModelStreamPart>[
      ToolInputEnd(call.id),
      ToolCall(
        toolCallId: call.id,
        toolName: call.name,
        input: call.arguments.toString(),
      ),
    ];
  }

  /// 流结束收尾：对所有未完成的调用按 `index` 升序补发
  /// [ToolInputEnd] + [ToolCall]（`arguments` 原样，即便不可解析——
  /// 与上游 flush 语义一致：flush 无条件调用 `finishToolCall`，不再探测
  /// 可解析性）。
  List<LanguageModelStreamPart> finishAll() {
    final indices = _calls.keys.toList()..sort();
    final events = <LanguageModelStreamPart>[];
    for (final index in indices) {
      final call = _calls[index]!;
      if (!call.hasFinished) {
        events.addAll(_finishCall(call));
      }
    }
    return events;
  }
}
