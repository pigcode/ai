import 'history.dart';
import 'models.dart';

enum AcpSessionRestoreKind {
  load,
  resume,
}

/// A completed load/resume operation; neither attaches to in-flight work.
final class AcpSessionRestoreResult<T extends AcpSchemaValue> {
  AcpSessionRestoreResult({
    required this.kind,
    required this.response,
    Iterable<AcpSessionUpdateEvent> historicalUpdates =
        const <AcpSessionUpdateEvent>[],
  }) : historicalUpdates =
            List<AcpSessionUpdateEvent>.unmodifiable(historicalUpdates);

  final AcpSessionRestoreKind kind;
  final T response;
  final List<AcpSessionUpdateEvent> historicalUpdates;

  bool get attachesToActivePrompt => false;
}
