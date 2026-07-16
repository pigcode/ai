import 'dart:convert';

import 'ui_message_chunk.dart';

/// Converts UI message chunks to Server-Sent Events data frames.
Stream<String> toUiMessageSseStream(
  Stream<UiMessageChunk> stream, {
  bool sendDone = true,
}) async* {
  await for (final chunk in stream) {
    yield 'data: ${jsonEncode(chunk.toJson())}\n\n';
  }
  if (sendDone) {
    yield 'data: [DONE]\n\n';
  }
}
