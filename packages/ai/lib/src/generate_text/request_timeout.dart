import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

/// Timeout controls for generation, streaming, and tool execution.
///
/// Passing a bare [Duration] to `generateText` or `streamText` remains the
/// shorthand for [total]. Structured configuration can additionally bound
/// each step, the first semantic stream chunk, gaps between semantic chunks,
/// and tool executions.
final class TimeoutConfiguration {
  const TimeoutConfiguration({
    this.total,
    this.step,
    this.firstChunk,
    this.chunk,
    this.tool,
    this.tools = const <String, Duration>{},
  });

  final Duration? total;
  final Duration? step;
  final Duration? firstChunk;
  final Duration? chunk;
  final Duration? tool;

  /// Per-tool overrides keyed by the public tool name.
  final Map<String, Duration> tools;

  Duration? forTool(String toolName) => tools[toolName] ?? tool;
}

TimeoutConfiguration normalizeTimeoutConfiguration(Object? timeout) {
  final configuration = switch (timeout) {
    null => const TimeoutConfiguration(),
    Duration duration => TimeoutConfiguration(total: duration),
    TimeoutConfiguration configuration => configuration,
    _ => throw ArgumentError.value(
        timeout,
        'timeout',
        'must be a Duration or TimeoutConfiguration',
      ),
  };

  final durations = <String, Duration?>{
    'total': configuration.total,
    'step': configuration.step,
    'firstChunk': configuration.firstChunk,
    'chunk': configuration.chunk,
    'tool': configuration.tool,
    for (final entry in configuration.tools.entries)
      'tools.${entry.key}': entry.value,
  };
  for (final entry in durations.entries) {
    if (entry.value case final duration?
        when duration.isNegative || duration == Duration.zero) {
      throw ArgumentError.value(
        duration,
        'timeout.${entry.key}',
        'must be greater than zero',
      );
    }
  }
  return TimeoutConfiguration(
    total: configuration.total,
    step: configuration.step,
    firstChunk: configuration.firstChunk,
    chunk: configuration.chunk,
    tool: configuration.tool,
    tools: Map<String, Duration>.unmodifiable(configuration.tools),
  );
}

TimeoutException timeoutException(String label, Duration duration) {
  return TimeoutException(
    '$label timeout of ${duration.inMilliseconds}ms exceeded',
    duration,
  );
}

/// A cancellable child scope. The first parent cancellation or local timeout
/// wins and its reason is preserved.
final class CancellationScope {
  CancellationScope({
    provider.CancellationSignal? parent,
    Duration? timeout,
    required String label,
    bool locallyCancellable = false,
  }) {
    if (parent == null && timeout == null && !locallyCancellable) {
      signal = null;
      return;
    }

    final controller = provider.CancellationController();
    _controller = controller;
    signal = controller.signal;

    if (parent != null) {
      if (parent.isCancelled) {
        controller.cancel(parent.reason);
      } else {
        unawaited(
          parent.whenCancelled.then((_) {
            if (!_disposed) {
              controller.cancel(parent.reason);
            }
          }),
        );
      }
    }
    if (timeout != null) {
      _timer = Timer(
        timeout,
        () => cancel(timeoutException(label, timeout)),
      );
    }
  }

  provider.CancellationController? _controller;
  Timer? _timer;
  bool _disposed = false;
  late final provider.CancellationSignal? signal;

  void cancel(Object? reason) {
    if (!_disposed) {
      _controller?.cancel(reason);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _timer?.cancel();
    _timer = null;
  }
}

void throwIfCancelled(provider.CancellationSignal? signal) {
  if (signal?.isCancelled ?? false) {
    throw signal!.reason ?? StateError('Generation cancelled');
  }
}

/// Forces an async operation that ignores [signal] to complete with the
/// cancellation reason when cancellation wins.
Future<T> interruptFutureOnCancellation<T>(
  FutureOr<T> operation,
  provider.CancellationSignal? signal,
) async {
  if (signal == null) {
    return operation;
  }
  throwIfCancelled(signal);
  return Future.any<T>(<Future<T>>[
    Future<T>.value(operation),
    signal.whenCancelled.then<T>((_) {
      throw signal.reason ?? StateError('Generation cancelled');
    }),
  ]);
}

/// Forces a stream that ignores [signal] to terminate when cancellation wins.
Stream<T> interruptOnCancellation<T>(
  Stream<T> source,
  provider.CancellationSignal? signal,
) {
  if (signal == null) {
    return source;
  }

  late final StreamSubscription<T> subscription;
  late final StreamController<T> controller;
  var terminal = false;

  void cancelSource() {
    unawaited(
      subscription.cancel().catchError((Object _) {
        // The cancellation winner has already become the public terminal.
        // A provider-side cancellation cleanup failure must not replace it.
      }),
    );
  }

  Future<void> terminateFromCancellation() async {
    if (terminal) {
      return;
    }
    terminal = true;
    controller.addError(
      signal.reason ?? StateError('Generation cancelled'),
    );
    cancelSource();
    await controller.close();
  }

  controller = StreamController<T>(
    sync: true,
    onListen: () {
      subscription = source.listen(
        (event) {
          if (!terminal) {
            controller.add(event);
          }
        },
        onError: (Object error, StackTrace stackTrace) {
          if (!terminal) {
            terminal = true;
            controller.addError(error, stackTrace);
            controller.close();
          }
        },
        onDone: () {
          if (!terminal) {
            terminal = true;
            controller.close();
          }
        },
      );
      if (signal.isCancelled) {
        unawaited(terminateFromCancellation());
      } else {
        unawaited(signal.whenCancelled.then((_) {
          return terminateFromCancellation();
        }));
      }
    },
    onPause: () => subscription.pause(),
    onResume: () => subscription.resume(),
    onCancel: () {
      terminal = true;
      cancelSource();
    },
  );
  return controller.stream;
}
