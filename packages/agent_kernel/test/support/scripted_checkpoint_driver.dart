final class ScriptedCheckpointDriver {
  ScriptedCheckpointDriver({
    required this.durableCheckpointResume,
    this.checkpointReference = 'checkpoint:test',
    this.loseResponse = false,
  });

  final bool durableCheckpointResume;
  final String checkpointReference;
  bool loseResponse;

  Future<String?> checkpoint() async {
    if (!durableCheckpointResume) {
      throw StateError('durableCheckpointResume is not supported.');
    }
    return loseResponse ? null : checkpointReference;
  }
}
