import 'dart:async';

/// 只读取消信号（映射上游 AbortSignal 的只读侧）。
///
/// 传给忽略它的模型时零行为变化：模型只需按需查询 [isCancelled]
/// 或监听 [whenCancelled]。身份对象，不参与值相等。
abstract interface class CancellationSignal {
  /// 是否已被取消。
  bool get isCancelled;

  /// 取消时完成的 future；正常收尾后不再触发副作用。
  Future<void> get whenCancelled;
}

/// 可写侧：核心/调用方持有，产出只读 [signal]。
///
/// 由内部 [Completer] 支撑；[cancel] 幂等（重复调用安全、不抛错）。
/// 身份对象，不参与值相等。
final class CancellationController {
  final Completer<void> _completer = Completer<void>();
  late final CancellationSignal _signal = _CancellationSignal(this);

  /// 该控制器暴露的只读信号（同一实例，多次读取一致）。
  CancellationSignal get signal => _signal;

  /// 是否已取消。
  bool get isCancelled => _completer.isCompleted;

  /// 触发取消：翻转 [isCancelled] 并完成 [signal.whenCancelled]。
  ///
  /// 幂等：已取消时再次调用为无操作，不抛异常。
  void cancel() {
    if (_completer.isCompleted) {
      return;
    }
    _completer.complete();
  }
}

/// [CancellationController] 内部的只读视图实现。
final class _CancellationSignal implements CancellationSignal {
  const _CancellationSignal(this._controller);

  final CancellationController _controller;

  @override
  bool get isCancelled => _controller.isCancelled;

  @override
  Future<void> get whenCancelled => _controller._completer.future;
}
