import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import 'step_result.dart';

/// 构造单步性能指标。
StepResultPerformance buildStepPerformance({
  required provider.LanguageModelUsage usage,
  required Duration responseTime,
  required Duration stepTime,
  Map<String, Duration> toolExecutionTimes = const {},
  Duration? timeToFirstOutput,
  OutputChunkTimingStats? timeBetweenOutputChunks,
}) {
  final inputTokens = usage.inputTokens.total;
  final outputTokens = usage.outputTokens.total;
  return StepResultPerformance(
    effectiveOutputTokensPerSecond: calculateTokensPerSecond(
      tokens: outputTokens,
      duration: responseTime,
    ),
    outputTokensPerSecond: timeToFirstOutput == null
        ? null
        : calculateTokensPerSecond(
            tokens: outputTokens,
            duration: responseTime - timeToFirstOutput,
          ),
    inputTokensPerSecond: timeToFirstOutput == null
        ? null
        : calculateTokensPerSecond(
            tokens: inputTokens,
            duration: timeToFirstOutput,
          ),
    effectiveTotalTokensPerSecond: calculateTokensPerSecond(
      tokens: sumTokenCounts(inputTokens, outputTokens),
      duration: responseTime,
    ),
    stepTime: stepTime,
    responseTime: responseTime,
    toolExecutionTimes: toolExecutionTimes,
    timeToFirstOutput: timeToFirstOutput,
    timeBetweenOutputChunks: timeBetweenOutputChunks,
  );
}

/// 计算 token/s。未知 token、未知/零耗时或不可表示的值均返回 0。
double calculateTokensPerSecond({
  required int? tokens,
  required Duration? duration,
}) {
  final microseconds = duration?.inMicroseconds ?? 0;
  if (tokens == null || microseconds <= 0) {
    return 0;
  }
  final rate = tokens * Duration.microsecondsPerSecond / microseconds;
  return rate.isFinite ? rate : 0;
}

/// 合并 token 数；两侧都未知时保持未知。
int? sumTokenCounts(int? first, int? second) =>
    first == null && second == null ? null : (first ?? 0) + (second ?? 0);

/// 计算输出分块间隔统计。空列表返回 `null`。
OutputChunkTimingStats? calculateOutputChunkTimingStats(
  List<Duration> timings,
) {
  if (timings.isEmpty) {
    return null;
  }
  final sorted = List<Duration>.of(timings)..sort((a, b) => a.compareTo(b));
  final totalMicroseconds = timings.fold<int>(
    0,
    (sum, timing) => sum + timing.inMicroseconds,
  );
  return OutputChunkTimingStats(
    min: sorted.first,
    p10: _nearestRankPercentile(sorted, 0.1),
    median: _nearestRankPercentile(sorted, 0.5),
    average: Duration(
      microseconds: totalMicroseconds ~/ timings.length,
    ),
    p90: _nearestRankPercentile(sorted, 0.9),
    max: sorted.last,
  );
}

Duration _nearestRankPercentile(
  List<Duration> sortedValues,
  double percentile,
) {
  final index = (percentile * sortedValues.length).ceil() - 1;
  return sortedValues[index];
}
