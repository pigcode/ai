import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart';

/// 可被 [cancellation] 提前中断的延时。
///
/// `Future.delayed` 本身不可取消,因此用 [Timer] 管理延时并与
/// [cancellation]`.whenCancelled` 竞速:若取消先于延时到达,清理定时器并
/// 以 [StateError] 结束(取消是控制流,不构造 `AiError` 子类,遵守"取消
/// 原样可识别、不包装为 API 错误"的契约语义)。[cancellation] 为 `null`
/// 或从未取消时,行为等价于普通 `Future.delayed(duration)`。
Future<void> delayCancellable(
  Duration duration, {
  CancellationSignal? cancellation,
}) {
  if (cancellation != null && cancellation.isCancelled) {
    return Future<void>.error(StateError('Delay was cancelled'));
  }

  final completer = Completer<void>();
  late final Timer timer;

  timer = Timer(duration, () {
    if (completer.isCompleted) {
      return;
    }
    completer.complete();
  });

  if (cancellation != null) {
    cancellation.whenCancelled.then((_) {
      if (completer.isCompleted) {
        return;
      }
      timer.cancel();
      completer.completeError(StateError('Delay was cancelled'));
    });
  }

  return completer.future.whenComplete(timer.cancel);
}
