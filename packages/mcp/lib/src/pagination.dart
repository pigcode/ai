import 'generated/mcp_models.g.dart';
import 'models.dart';

/// Creates pagination parameters without interpreting the cursor.
McpPaginatedRequestParams mcpPageRequest({String? cursor}) =>
    McpPaginatedRequestParams.fromJson(
      <String, Object?>{
        if (cursor != null) 'cursor': cursor,
      },
    );

/// A validated MCP page together with its opaque continuation cursor.
final class McpPage<T extends McpSchemaValue> {
  McpPage(this.result)
      : nextCursor = switch (result.toJson()) {
          final Map<String, Object?> value when value['nextCursor'] is String =>
            value['nextCursor']! as String,
          _ => null,
        };

  final T result;
  final String? nextCursor;

  bool get hasNext => nextCursor != null;

  McpPaginatedRequestParams nextRequest() {
    final cursor = nextCursor;
    if (cursor == null) {
      throw StateError('This MCP page has no next cursor.');
    }
    return mcpPageRequest(cursor: cursor);
  }
}
