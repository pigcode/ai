/// Incrementally converts bounded byte chunks into complete protocol frames.
abstract interface class ProtocolFramer<T> {
  /// Adds bytes and returns every frame completed by this chunk.
  List<T> add(List<int> bytes);

  /// Finishes the stream and returns any frames completed by EOF.
  List<T> close();

  /// Bytes retained by the current incomplete frame.
  int get bufferedByteCount;

  /// Whether the framer has closed successfully.
  bool get isClosed;
}
