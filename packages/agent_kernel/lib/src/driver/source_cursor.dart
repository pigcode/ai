final class DriverSourceCursor {
  DriverSourceCursor({
    required this.sourceId,
    this.lastOrdinal = 0,
    Map<int, String> recentDigests = const <int, String>{},
    this.maximumRememberedOrdinals = 128,
  }) : recentDigests = Map<int, String>.unmodifiable(recentDigests);

  final String sourceId;
  final int lastOrdinal;
  final Map<int, String> recentDigests;
  final int maximumRememberedOrdinals;

  DriverSourceCursor advance(int ordinal, String digest) {
    final next = <int, String>{...recentDigests, ordinal: digest};
    final ordinals = next.keys.toList()..sort();
    while (ordinals.length > maximumRememberedOrdinals) {
      next.remove(ordinals.removeAt(0));
    }
    return DriverSourceCursor(
      sourceId: sourceId,
      lastOrdinal: ordinal,
      recentDigests: next,
      maximumRememberedOrdinals: maximumRememberedOrdinals,
    );
  }
}
