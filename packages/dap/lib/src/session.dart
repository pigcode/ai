/// Idempotent terminal facts from racing DAP events and disconnect.
final class DapSessionTerminal {
  bool terminated = false;
  bool exited = false;
  bool disconnected = false;
  int? exitCode;
  int terminalTransitionCount = 0;

  bool recordTerminated() {
    terminated = true;
    return _recordTerminalEdge();
  }

  bool recordExited({required int exitCode}) {
    exited = true;
    this.exitCode = exitCode;
    return _recordTerminalEdge();
  }

  bool recordDisconnected() {
    disconnected = true;
    return _recordTerminalEdge();
  }

  bool _recordTerminalEdge() {
    if (terminalTransitionCount != 0) {
      return false;
    }
    terminalTransitionCount = 1;
    return true;
  }
}
