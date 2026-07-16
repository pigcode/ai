import '../generate_text/text_stream_part.dart';

/// Converts text stream parts to plain text deltas.
Stream<String> toTextStream(Stream<TextStreamPart> stream) async* {
  await for (final part in stream) {
    if (part is TextDeltaPart) {
      yield part.delta;
    }
  }
}
