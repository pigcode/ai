import 'package:json_schema/json_schema.dart' as upstream;

/// Explicit draft-04 validator rooted at one named definition.
final class Draft04Validator {
  Draft04Validator._(this._validator);

  static const dialect = 'http://json-schema.org/draft-04/schema#';

  final upstream.JsonSchema _validator;

  factory Draft04Validator.fromDocument(
    Map<String, Object?> document, {
    required String entryRef,
  }) {
    _validateEntry(document, entryRef);
    return Draft04Validator._(
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
      throw const FormatException('Expected JSON Schema draft-04.');
    }
    const prefix = '#/definitions/';
    if (!entryRef.startsWith(prefix) || entryRef.length == prefix.length) {
      throw const FormatException(
        'Draft-04 validation requires a concrete definition entry ref.',
      );
    }
    final definitions = document['definitions'];
    if (definitions is! Map<String, Object?> ||
        !definitions.containsKey(entryRef.substring(prefix.length))) {
      throw FormatException('Unknown draft-04 entry ref: $entryRef.');
    }
  }
}
