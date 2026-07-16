import 'dart:async';

import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:pigcode_ai_provider_utils/pigcode_ai_provider_utils.dart'
    as utils;

import 'output_utils.dart';
import 'parse_partial_json.dart';

sealed class Output<Complete, Partial, Element> {
  const Output();

  String get name;

  FutureOr<Complete> parseCompleteOutput(
    OutputText text,
    OutputParseContext context,
  );

  FutureOr<PartialOutput<Partial>?> parsePartialOutput(String text);

  Stream<Element>? createElementStream(Stream<Partial> partials);

  static TextOutput text() => const TextOutput();

  static ObjectOutput object({
    required provider.JsonSchema schema,
    String? name,
    String? description,
  }) {
    return ObjectOutput(
      schema: schema,
      responseName: name,
      description: description,
    );
  }

  static ArrayOutput array({
    required provider.JsonSchema element,
    String? name,
    String? description,
  }) {
    return ArrayOutput(
      element: element,
      responseName: name,
      description: description,
    );
  }

  static ChoiceOutput choice({
    required List<String> options,
    String? name,
    String? description,
  }) {
    return ChoiceOutput(
      options: options,
      responseName: name,
      description: description,
    );
  }

  static JsonOutput json({String? name, String? description}) {
    return JsonOutput(responseName: name, description: description);
  }
}

final class PartialOutput<Partial> {
  const PartialOutput(this.partial);

  final Partial partial;
}

provider.ResponseFormat outputResponseFormat(
  Output<Object?, Object?, Object?> output,
) {
  if (output is TextOutput) {
    return const provider.ResponseFormatText();
  }
  if (output is ObjectOutput) {
    return provider.ResponseFormatJson(
      schema: output.schema,
      name: output._responseName,
      description: output.description,
    );
  }
  if (output is ArrayOutput) {
    return provider.ResponseFormatJson(
      schema: output._schema,
      name: output._responseName,
      description: output.description,
    );
  }
  if (output is ChoiceOutput) {
    return provider.ResponseFormatJson(
      schema: output._schema,
      name: output._responseName,
      description: output.description,
    );
  }
  if (output is JsonOutput) {
    return provider.ResponseFormatJson(
      name: output._responseName,
      description: output.description,
    );
  }
  throw StateError('Unsupported output mode: ${output.name}');
}

final class OutputText {
  const OutputText(this.text);

  final String text;
}

final class OutputParseContext {
  const OutputParseContext({
    this.response,
    required this.usage,
    required this.finishReason,
  });

  final provider.ResponseInfo? response;
  final provider.LanguageModelUsage usage;
  final provider.LanguageModelFinishReason finishReason;
}

final class TextOutput extends Output<String, String, Never> {
  const TextOutput();

  @override
  String get name => 'text';

  @override
  String parseCompleteOutput(OutputText text, OutputParseContext context) {
    return text.text;
  }

  @override
  PartialOutput<String> parsePartialOutput(String text) {
    return PartialOutput(text);
  }

  @override
  Stream<Never>? createElementStream(Stream<String> partials) {
    return null;
  }
}

final class ObjectOutput
    extends Output<provider.JsonObject, provider.JsonObject, Never> {
  ObjectOutput({
    required provider.JsonSchema schema,
    String? responseName,
    String? description,
  }) : this._(
          schema: freezeJsonSchema(schema),
          responseName: responseName,
          description: description,
        );

  ObjectOutput._({
    required this.schema,
    String? responseName,
    this.description,
  })  : _responseName = responseName,
        _validator = utils.JsonSchemaValidator.fromContract(schema);

  final provider.JsonSchema schema;
  final String? _responseName;
  final String? description;
  final utils.JsonSchemaValidator _validator;

  @override
  String get name => 'object';

  @override
  provider.JsonObject parseCompleteOutput(
    OutputText text,
    OutputParseContext context,
  ) {
    final value = _parseJsonOrThrow(
      text.text,
      context,
      'No object generated: could not parse the response.',
    );
    final object = _asJsonObject(value);
    if (object == null) {
      throw _noObjectGenerated(
        text: text.text,
        context: context,
        message: 'No object generated: response did not match schema.',
        cause: provider.TypeValidationError(
          value: value,
          cause: 'response must be an object.',
        ),
      );
    }
    _validateOrThrow(object, _validator, text.text, context);
    return object;
  }

  @override
  PartialOutput<provider.JsonObject>? parsePartialOutput(String text) {
    final partial = parsePartialJson(text);
    if (partial.state == PartialJsonState.failedParse ||
        partial.state == PartialJsonState.undefinedInput) {
      return null;
    }
    final object = _asJsonObject(partial.value);
    return object == null ? null : PartialOutput(object);
  }

  @override
  Stream<Never>? createElementStream(Stream<provider.JsonObject> partials) {
    return null;
  }
}

final class ArrayOutput extends Output<List<provider.JsonValue>,
    List<provider.JsonValue>, provider.JsonValue> {
  ArrayOutput({
    required this.element,
    String? responseName,
    this.description,
  })  : _responseName = responseName,
        _schema = arrayWrapperSchema(element),
        _elementValidator = utils.JsonSchemaValidator.fromContract(element);

  final provider.JsonSchema element;
  final String? _responseName;
  final String? description;
  final provider.JsonSchema _schema;
  final utils.JsonSchemaValidator _elementValidator;

  @override
  String get name => 'array';

  @override
  List<provider.JsonValue> parseCompleteOutput(
    OutputText text,
    OutputParseContext context,
  ) {
    final value = _parseJsonOrThrow(
      text.text,
      context,
      'No object generated: could not parse the response.',
    );
    final elements = _extractElements(value, allowExtraProperties: false);
    if (elements == null) {
      throw _noObjectGenerated(
        text: text.text,
        context: context,
        message: 'No object generated: response did not match schema.',
        cause: provider.TypeValidationError(
          value: value,
          cause: 'response must be an object with an elements array',
        ),
      );
    }

    for (final element in elements) {
      _validateOrThrow(element, _elementValidator, text.text, context);
    }
    return List<provider.JsonValue>.unmodifiable(elements);
  }

  @override
  PartialOutput<List<provider.JsonValue>>? parsePartialOutput(String text) {
    final partial = parsePartialJson(text);
    if (partial.state == PartialJsonState.failedParse ||
        partial.state == PartialJsonState.undefinedInput) {
      return null;
    }
    final elements = _extractElements(partial.value);
    if (elements == null) {
      return null;
    }

    final dropTrailingElement =
        partial.state == PartialJsonState.repairedParse &&
            elements.isNotEmpty &&
            _hasIncompleteTrailingArrayElement(text);
    final candidates = dropTrailingElement
        ? elements.sublist(0, elements.length - 1)
        : elements;
    final validated = <provider.JsonValue>[];
    for (final element in candidates) {
      if (_elementValidator.validate(element) is utils.ValidationSuccess) {
        validated.add(element);
      }
    }
    return PartialOutput(List<provider.JsonValue>.unmodifiable(validated));
  }

  @override
  Stream<provider.JsonValue> createElementStream(
    Stream<List<provider.JsonValue>> partials,
  ) async* {
    var publishedElements = 0;

    await for (final partial in partials) {
      // Element streams are an append-only projection. Already published
      // indexes are never withdrawn or replaced, so partial rollback or
      // replacement does not re-publish existing indexes.
      while (publishedElements < partial.length) {
        yield partial[publishedElements];
        publishedElements++;
      }
    }
  }
}

bool _hasIncompleteTrailingArrayElement(String text) {
  final arrayStart = _findElementsArrayStart(text);
  if (arrayStart == null) {
    return false;
  }

  var inString = false;
  var escaped = false;
  var depth = 0;
  var hasStartedElement = false;
  var elementComplete = false;

  for (var i = arrayStart + 1; i < text.length; i++) {
    final char = text[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (char == r'\') {
        escaped = true;
      } else if (char == '"') {
        inString = false;
        if (depth == 0 && hasStartedElement) {
          elementComplete = true;
        }
      }
      continue;
    }

    if (char.trim().isEmpty) {
      continue;
    }

    if (depth == 0) {
      if (char == ']') {
        return false;
      }
      if (char == ',') {
        hasStartedElement = false;
        elementComplete = false;
        continue;
      }
      if (!hasStartedElement) {
        hasStartedElement = true;
        elementComplete = false;
        if (char == '{' || char == '[') {
          depth = 1;
        } else if (char == '"') {
          inString = true;
        }
      }
      continue;
    }

    if (char == '"') {
      inString = true;
    } else if (char == '{' || char == '[') {
      depth++;
    } else if (char == '}' || char == ']') {
      depth--;
      if (depth == 0) {
        elementComplete = true;
      }
    }
  }

  return hasStartedElement && !elementComplete;
}

int? _findElementsArrayStart(String text) {
  final match = RegExp(r'"elements"\s*:\s*\[').firstMatch(text);
  return match == null ? null : match.end - 1;
}

final class ChoiceOutput extends Output<String, String, Never> {
  ChoiceOutput({
    required List<String> options,
    String? responseName,
    this.description,
  })  : options = _validateOptions(options),
        _responseName = responseName {
    _schema = choiceWrapperSchema(this.options);
  }

  final List<String> options;
  final String? _responseName;
  final String? description;
  late final provider.JsonSchema _schema;

  @override
  String get name => 'choice';

  @override
  String parseCompleteOutput(OutputText text, OutputParseContext context) {
    final value = _parseJsonOrThrow(
      text.text,
      context,
      'No object generated: could not parse the response.',
    );
    final choice = _extractChoice(value, allowExtraProperties: false);
    if (choice == null || !options.contains(choice)) {
      throw _noObjectGenerated(
        text: text.text,
        context: context,
        message: 'No object generated: response did not match schema.',
        cause: provider.TypeValidationError(
          value: value,
          cause: 'response must be an object that contains a choice value.',
        ),
      );
    }
    return choice;
  }

  @override
  PartialOutput<String>? parsePartialOutput(String text) {
    final partial = parsePartialJson(text);
    if (partial.state == PartialJsonState.failedParse ||
        partial.state == PartialJsonState.undefinedInput) {
      return null;
    }
    final choice = _extractChoice(partial.value);
    if (choice == null) {
      return null;
    }
    if (partial.state == PartialJsonState.successfulParse) {
      return options.contains(choice) ? PartialOutput(choice) : null;
    }

    final matches =
        options.where((option) => option.startsWith(choice)).toList();
    return matches.length == 1 ? PartialOutput(matches.single) : null;
  }

  @override
  Stream<Never>? createElementStream(Stream<String> partials) {
    return null;
  }
}

final class JsonOutput
    extends Output<provider.JsonValue, provider.JsonValue, Never> {
  const JsonOutput({String? responseName, this.description})
      : _responseName = responseName;

  final String? _responseName;
  final String? description;

  @override
  String get name => 'json';

  @override
  provider.JsonValue parseCompleteOutput(
    OutputText text,
    OutputParseContext context,
  ) {
    return _parseJsonOrThrow(
      text.text,
      context,
      'No object generated: could not parse the response.',
    );
  }

  @override
  PartialOutput<provider.JsonValue>? parsePartialOutput(String text) {
    final partial = parsePartialJson(text);
    return switch (partial.state) {
      PartialJsonState.successfulParse ||
      PartialJsonState.repairedParse =>
        PartialOutput(partial.value),
      PartialJsonState.failedParse || PartialJsonState.undefinedInput => null,
    };
  }

  @override
  Stream<Never>? createElementStream(Stream<provider.JsonValue> partials) {
    return null;
  }
}

provider.JsonValue _parseJsonOrThrow(
  String text,
  OutputParseContext context,
  String message,
) {
  final parsed = utils.safeParseJson(text);
  return switch (parsed) {
    utils.ParseSuccess<provider.JsonValue>(:final value) => value,
    utils.ParseFailure<provider.JsonValue>(:final error) =>
      throw _noObjectGenerated(
        text: text,
        context: context,
        message: message,
        cause: error,
      ),
  };
}

provider.NoObjectGeneratedError _noObjectGenerated({
  required String text,
  required OutputParseContext context,
  required String message,
  required Object cause,
}) {
  return provider.NoObjectGeneratedError(
    message: message,
    cause: cause,
    text: text,
    response: context.response,
    usage: context.usage,
    finishReason: context.finishReason,
  );
}

void _validateOrThrow(
  provider.JsonValue value,
  utils.JsonSchemaValidator validator,
  String text,
  OutputParseContext context,
) {
  final validation = validator.validate(value);
  if (validation is utils.ValidationFailure) {
    throw _noObjectGenerated(
      text: text,
      context: context,
      message: 'No object generated: response did not match schema.',
      cause: validation.error,
    );
  }
}

provider.JsonObject? _asJsonObject(provider.JsonValue value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, Object?>.unmodifiable(value);
  }
  return null;
}

List<provider.JsonValue>? _extractElements(
  provider.JsonValue value, {
  bool allowExtraProperties = true,
}) {
  final object = _asJsonObject(value);
  if (object == null) {
    return null;
  }
  if (!allowExtraProperties && object.length != 1) {
    return null;
  }
  final elements = object['elements'];
  if (elements is! List) {
    return null;
  }
  return List<provider.JsonValue>.from(elements);
}

String? _extractChoice(
  provider.JsonValue value, {
  bool allowExtraProperties = true,
}) {
  final object = _asJsonObject(value);
  if (object == null) {
    return null;
  }
  if (!allowExtraProperties && object.length != 1) {
    return null;
  }
  final result = object['result'];
  return result is String ? result : null;
}

List<String> _validateOptions(List<String> options) {
  if (options.isEmpty) {
    throw const provider.InvalidArgumentError(
      argument: 'options',
      message: 'options must contain at least one choice.',
    );
  }
  if (options.any((option) => option.isEmpty)) {
    throw const provider.InvalidArgumentError(
      argument: 'options',
      message: 'options must not contain empty strings.',
    );
  }
  if (options.toSet().length != options.length) {
    throw const provider.InvalidArgumentError(
      argument: 'options',
      message: 'options must not contain duplicate choices.',
    );
  }
  return List<String>.unmodifiable(options);
}
