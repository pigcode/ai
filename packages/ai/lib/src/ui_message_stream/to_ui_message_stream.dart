import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;

import '../generate_text/text_stream_part.dart';
import 'to_ui_message_chunk.dart';
import 'ui_message_chunk.dart';

/// Converts text stream parts to UI message chunks.
Stream<UiMessageChunk> toUiMessageStream(
  Stream<TextStreamPart> stream, {
  bool sendReasoning = true,
  bool sendStart = true,
  bool sendFinish = true,
  UiMessageErrorText onError = defaultUiMessageErrorText,
  String? responseMessageId,
  provider.JsonObject? Function(TextStreamPart part)? messageMetadata,
}) async* {
  await for (final part in stream) {
    final metadata = messageMetadata?.call(part);
    final isMetadataInlinedPart = part is StartPart ||
        part is FinishPart ||
        part is ErrorPart ||
        part is AbortPart;
    final chunk = toUiMessageChunk(
      part,
      sendReasoning: sendReasoning,
      sendStart: sendStart,
      sendFinish: sendFinish,
      onError: onError,
      responseMessageId: responseMessageId,
      messageMetadata: isMetadataInlinedPart ? metadata : null,
    );

    if (chunk != null) {
      yield chunk;
    }
    if (metadata != null && !isMetadataInlinedPart) {
      yield MessageMetadataUiMessageChunk(metadata);
    }
  }
}
