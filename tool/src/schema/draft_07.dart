import 'package:json_schema/json_schema.dart' as upstream;

/// Explicit draft-07 validator rooted at one named definition.
final class Draft07Validator {
  Draft07Validator._(this._validator);

  static const dialect = 'http://json-schema.org/draft-07/schema#';

  final upstream.JsonSchema _validator;

  factory Draft07Validator.fromDocument(
    Map<String, Object?> document, {
    required String entryRef,
  }) {
    _validateEntry(document, entryRef);
    return Draft07Validator._(
      upstream.JsonSchema.create(<String, Object?>{
        ...document,
        r'$ref': entryRef,
      }),
    );
  }

  bool isValid(Object? value) => _validator.validate(value).isValid;

  static void _validateEntry(
    Map<String, Object?> document,
    String entryRef,
  ) {
    if (document[r'$schema'] != dialect) {
      throw const FormatException('Expected JSON Schema draft-07.');
    }
    const prefix = '#/definitions/';
    if (!entryRef.startsWith(prefix) || entryRef.length == prefix.length) {
      throw const FormatException(
        'Draft-07 validation requires a named definition entry ref.',
      );
    }
    final definitions = document['definitions'];
    if (definitions is! Map<String, Object?> ||
        !definitions.containsKey(entryRef.substring(prefix.length))) {
      throw FormatException('Unknown draft-07 entry ref: $entryRef.');
    }
  }
}
