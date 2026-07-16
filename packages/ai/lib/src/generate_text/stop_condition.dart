import 'dart:async';

import 'step_result.dart';

/// 单次「是否停止工具循环」判定。
///
/// 输入是截至目前已产出的全部步骤([StepResult] 列表,末尾为最新一步);
/// 返回 `true` 表示应当停止循环,`false` 表示继续下一步。支持同步或
/// 异步(`Future<bool>`)实现。
///
/// `generateText`/`streamText` 的 `stopWhen` 接受单个 [StopCondition] 或
/// `List<StopCondition>`(任一条件为真即停止)。**不传 `stopWhen` 等价于
/// 单步**:第一步结束后即停止,不会进入多步工具循环。
typedef StopCondition = FutureOr<bool> Function(List<StepResult> steps);

/// 已完成步数等于 [stepCount] 时停止。[stepCount] 必须大于零。
///
/// 常见用法:`isStepCount(1)` 令循环在第一步后立即截断;
/// `isStepCount(20)` 之类的值可作为多步 agent 场景的安全上限。
StopCondition isStepCount(int stepCount) {
  if (stepCount <= 0) {
    throw ArgumentError.value(
      stepCount,
      'stepCount',
      'must be greater than zero',
    );
  }
  return (steps) => steps.length == stepCount;
}

/// 永不主动停止循环。
///
/// 这允许工具循环持续运行,直到遇到自然终止条件:模型不再返回工具调用、
/// 工具缺少 execute、工具调用需要审批,或外层执行过程中产生终止错误。
StopCondition isLoopFinished() => (steps) => false;

/// 当最新一步中存在 [toolName] 或任一 [additionalToolNames] 对应的工具调用时停止。
///
/// 只检查 `steps` 的最后一步(即最新产出的一步),历史步骤中出现过的
/// 同名调用不影响判定;步骤列表为空时返回 `false`。
StopCondition hasToolCall(
  String toolName, [
  List<String> additionalToolNames = const [],
]) {
  final toolNameSet = Set<String>.unmodifiable([
    toolName,
    ...additionalToolNames,
  ]);
  return (steps) =>
      steps.isNotEmpty &&
      steps.last.toolCalls.any((call) => toolNameSet.contains(call.toolName));
}
