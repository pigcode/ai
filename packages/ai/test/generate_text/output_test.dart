import 'package:pigcode_ai/pigcode_ai.dart';
import 'package:pigcode_ai/src/generate_text/output.dart' as output_internal;
import 'package:pigcode_ai_provider/pigcode_ai_provider.dart' as provider;
import 'package:test/test.dart';

const _usage = LanguageModelUsage(
  inputTokens: InputTokens(total: 1),
  outputTokens: OutputTokens(total: 1),
);
const _finishReason = LanguageModelFinishReason(FinishReasonType.stop);

final _context = OutputParseContext(
  response: const ResponseInfo(id: 'response-1'),
  usage: _usage,
  finishReason: _finishReason,
);

Future<provider.ResponseFormat> _responseFormat(
  Output<Object?, Object?, Object?> output,
) {
  return Future<provider.ResponseFormat>.value(
    output_internal.outputResponseFormat(output),
  );
}

Future<Object?> _complete(
  Output<Object?, Object?, Object?> output,
  String text,
) {
  return Future<Object?>.value(
    output.parseCompleteOutput(OutputText(text), _context),
  );
}

Future<Object?> _partial(
  Output<Object?, Object?, Object?> output,
  String text,
) async {
  final partial = await Future<PartialOutput<Object?>?>.value(
    output.parsePartialOutput(text),
  );
  return partial?.partial;
}

void main() {
  // Compatibility fixture (unit): P1-CORE-07
  group('Output.text', () {
    test('uses text response format and parses complete and partial text',
        () async {
      final output = Output.text();

      expect(
        await _responseFormat(output),
        isA<provider.ResponseFormatText>(),
      );
      expect(await _complete(output, 'hello'), 'hello');
      expect(await _partial(output, 'hel'), 'hel');
    });
  });

  group('Output.object', () {
    const schema = JsonSchema(<String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'a': <String, Object?>{'type': 'number'},
      },
      'required': <Object?>['a'],
    });

    test('uses JSON response format with schema, name, and description',
        () async {
      final output = Output.object(
        schema: schema,
        name: 'answer',
        description: 'An answer object.',
      );

      final format = await _responseFormat(output);
      expect(format, isA<provider.ResponseFormatJson>());
      final jsonFormat = format as provider.ResponseFormatJson;
      expect(jsonFormat.schema, schema);
      expect(jsonFormat.name, 'answer');
      expect(jsonFormat.description, 'An answer object.');
    });

    test('schema is deeply copied and immutable', () async {
      final aProperty = <String, Object?>{'type': 'number'};
      final properties = <String, Object?>{'a': aProperty};
      final sourceSchema = JsonSchema(<String, Object?>{
        'type': 'object',
        'properties': properties,
        'required': <Object?>['a'],
      });
      final output = Output.object(schema: sourceSchema);

      properties['b'] = <String, Object?>{'type': 'string'};
      aProperty['type'] = 'string';

      final format = await _responseFormat(output);
      final schema = (format as provider.ResponseFormatJson).schema!;
      final objectProperties =
          schema.value['properties'] as Map<String, Object?>;
      final objectA = objectProperties['a'] as Map<String, Object?>;

      expect(objectProperties.containsKey('b'), isFalse);
      expect(objectA['type'], 'number');
      expect(() => schema.value['extra'] = true, throwsUnsupportedError);
      expect(
        () => objectProperties['b'] = <String, Object?>{'type': 'string'},
        throwsUnsupportedError,
      );
      expect(() => objectA['type'] = 'integer', throwsUnsupportedError);
      expect(await _complete(output, '{"a":1}'), <String, Object?>{'a': 1});
    });

    test('parses complete JSON object and validates schema', () async {
      final output = Output.object(schema: schema);

      expect(await _complete(output, '{"a":1}'), <String, Object?>{'a': 1});
    });

    test('wraps parse failures in NoObjectGeneratedError', () {
      final output = Output.object(schema: schema);

      expect(
        () => output.parseCompleteOutput(OutputText('not json'), _context),
        throwsA(
          isA<NoObjectGeneratedError>()
              .having(
                (error) => error.message,
                'message',
                'No object generated: could not parse the response.',
              )
              .having((error) => error.cause, 'cause', isA<JsonParseError>())
              .having(
                (error) => error.response,
                'response',
                _context.response,
              )
              .having((error) => error.usage, 'usage', _context.usage)
              .having(
                (error) => error.finishReason,
                'finishReason',
                _context.finishReason,
              ),
        ),
      );
    });

    test('wraps schema failures in NoObjectGeneratedError', () {
      final output = Output.object(schema: schema);

      expect(
        () => output.parseCompleteOutput(OutputText('{"a":"bad"}'), _context),
        throwsA(
          isA<NoObjectGeneratedError>()
              .having(
                (error) => error.message,
                'message',
                'No object generated: response did not match schema.',
              )
              .having(
                (error) => error.cause,
                'cause',
                isA<TypeValidationError>(),
              ),
        ),
      );
    });

    test(
        'partial parse returns repaired JSON objects without schema validation',
        () async {
      final output = Output.object(schema: schema);

      expect(await _partial(output, '{"a":"in progress"'), <String, Object?>{
        'a': 'in progress',
      });
      expect(await _partial(output, 'not json'), isNull);
    });
  });

  group('Output.array', () {
    const elementSchema = JsonSchema(<String, Object?>{
      r'$schema': 'https://json-schema.org/draft-07/schema#',
      'type': 'object',
      'properties': <String, Object?>{
        'id': <String, Object?>{'type': 'number'},
      },
      'required': <Object?>['id'],
    });

    test('uses object wrapper with elements array and strips item \$schema',
        () async {
      final output = Output.array(element: elementSchema);

      final format = await _responseFormat(output);
      expect(format, isA<provider.ResponseFormatJson>());
      final schema = (format as provider.ResponseFormatJson).schema!;
      expect(
          schema.value[r'$schema'], 'http://json-schema.org/draft-07/schema#');
      expect(schema.value['type'], 'object');
      expect(schema.value['additionalProperties'], isFalse);
      final properties = schema.value['properties'] as Map<String, Object?>;
      final elements = properties['elements'] as Map<String, Object?>;
      expect(elements['type'], 'array');
      final items = elements['items'] as Map<String, Object?>;
      expect(items[r'$schema'], isNull);
      expect(items['type'], 'object');
    });

    test('hoists element \$defs to the wrapper schema root', () async {
      final output = Output.array(
        element: const JsonSchema(<String, Object?>{
          r'$schema': 'https://json-schema.org/draft-07/schema#',
          r'$ref': '#/\$defs/item',
          r'$defs': <String, Object?>{
            'item': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'id': <String, Object?>{'type': 'number'},
              },
              'required': <Object?>['id'],
            },
          },
        }),
      );

      final format = await _responseFormat(output);
      final schema = (format as provider.ResponseFormatJson).schema!;
      final properties = schema.value['properties'] as Map<String, Object?>;
      final elements = properties['elements'] as Map<String, Object?>;
      final items = elements['items'] as Map<String, Object?>;

      expect(schema.value[r'$defs'], isA<Map<String, Object?>>());
      expect(items[r'$defs'], isNull);
      expect(items[r'$ref'], '#/\$defs/item');
    });

    test('wrapper schema is deeply copied and immutable', () async {
      final idProperty = <String, Object?>{'type': 'number'};
      final properties = <String, Object?>{'id': idProperty};
      final sourceSchema = JsonSchema(<String, Object?>{
        r'$schema': 'https://json-schema.org/draft-07/schema#',
        'type': 'object',
        'properties': properties,
      });
      final output = Output.array(element: sourceSchema);

      properties['name'] = <String, Object?>{'type': 'string'};
      idProperty['type'] = 'string';

      final format = await _responseFormat(output);
      final schema = (format as provider.ResponseFormatJson).schema!;
      final wrapperProperties =
          schema.value['properties'] as Map<String, Object?>;
      final elements = wrapperProperties['elements'] as Map<String, Object?>;
      final items = elements['items'] as Map<String, Object?>;
      final itemProperties = items['properties'] as Map<String, Object?>;
      final itemId = itemProperties['id'] as Map<String, Object?>;

      expect(itemProperties.containsKey('name'), isFalse);
      expect(itemId['type'], 'number');
      expect(() => schema.value['extra'] = true, throwsUnsupportedError);
      expect(() => elements['maxItems'] = 3, throwsUnsupportedError);
      expect(() => itemId['type'] = 'integer', throwsUnsupportedError);
    });

    test('parses complete wrapper and validates each element', () async {
      final output = Output.array(element: elementSchema);

      expect(
        await _complete(output, '{"elements":[{"id":1},{"id":2}]}'),
        <Object?>[
          <String, Object?>{'id': 1},
          <String, Object?>{'id': 2},
        ],
      );
    });

    test('rejects complete wrappers with extra top-level fields', () {
      final output = Output.array(element: elementSchema);

      expect(
        () => output.parseCompleteOutput(
          OutputText('{"elements":[{"id":1}],"extra":true}'),
          _context,
        ),
        throwsA(isA<NoObjectGeneratedError>()),
      );
    });

    test('partial repaired arrays drop the in-progress last element', () async {
      final output = Output.array(element: elementSchema);

      expect(
        await _partial(output, '{"elements":[{"id":1},{"id":'),
        <Object?>[
          <String, Object?>{'id': 1},
        ],
      );
    });

    test('partial repaired arrays keep completed trailing elements', () async {
      final output = Output.array(element: elementSchema);

      expect(
        await _partial(output, '{"elements":[{"id":1}]'),
        <Object?>[
          <String, Object?>{'id': 1},
        ],
      );
      expect(
        await _partial(output, '{"elements":[{"id":1},'),
        <Object?>[
          <String, Object?>{'id': 1},
        ],
      );
    });

    test('createElementStream emits only newly observed elements', () async {
      final output = Output.array(element: elementSchema);

      final stream = output.createElementStream(
        Stream<List<JsonValue>>.fromIterable([
          [
            <String, Object?>{'id': 1},
          ],
          [
            <String, Object?>{'id': 1},
            <String, Object?>{'id': 2},
          ],
          [
            <String, Object?>{'id': 1},
            <String, Object?>{'id': 2},
          ],
          [
            <String, Object?>{'id': 1},
            <String, Object?>{'id': 2},
            <String, Object?>{'id': 3},
          ],
        ]),
      );

      expect(
        await stream.toList(),
        <Object?>[
          <String, Object?>{'id': 1},
          <String, Object?>{'id': 2},
          <String, Object?>{'id': 3},
        ],
      );
    });

    test('createElementStream is append-only across rollback and replacement',
        () async {
      final output = Output.array(element: elementSchema);

      final stream = output.createElementStream(
        Stream<List<JsonValue>>.fromIterable([
          [1],
          [1, 2],
          [1],
          [1, 3],
          [1, 3, 4],
        ]),
      );

      expect(await stream.toList(), <Object?>[1, 2, 4]);
    });
  });

  group('Output.choice', () {
    test('uses result enum wrapper and parses a complete choice', () async {
      final output = Output.choice(options: ['red', 'blue']);

      final format = await _responseFormat(output);
      expect(format, isA<provider.ResponseFormatJson>());
      final schema = (format as provider.ResponseFormatJson).schema!;
      expect(
          schema.value[r'$schema'], 'http://json-schema.org/draft-07/schema#');
      expect(schema.value['additionalProperties'], isFalse);
      final properties = schema.value['properties'] as Map<String, Object?>;
      final result = properties['result'] as Map<String, Object?>;
      expect(result['enum'], <Object?>['red', 'blue']);
      expect(() => schema.value['extra'] = true, throwsUnsupportedError);
      expect(() => result['type'] = 'number', throwsUnsupportedError);
      expect(
        () => (result['enum'] as List<Object?>).add('green'),
        throwsUnsupportedError,
      );
      expect(await _complete(output, '{"result":"red"}'), 'red');
    });

    test('rejects complete choices with extra top-level fields', () {
      final output = Output.choice(options: ['red', 'blue']);

      expect(
        () => output.parseCompleteOutput(
          const OutputText('{"result":"red","extra":true}'),
          _context,
        ),
        throwsA(isA<NoObjectGeneratedError>()),
      );
    });

    test('rejects empty, duplicate, and empty-string options', () {
      for (final options in <List<String>>[
        const [],
        const ['red', 'red'],
        const [''],
      ]) {
        expect(
          () => Output.choice(options: options),
          throwsA(
            isA<InvalidArgumentError>()
                .having((error) => error.argument, 'argument', 'options'),
          ),
        );
      }
    });

    test('partial repaired choices return only unambiguous prefixes', () async {
      final output = Output.choice(options: ['red', 'rose', 'blue']);

      expect(await _partial(output, '{"result":"blu'), 'blue');
      expect(await _partial(output, '{"result":"r'), isNull);
      expect(await _partial(output, '{"result":"red"}'), 'red');
    });
  });

  group('Output.json', () {
    test('uses JSON response format and parses arbitrary JSON', () async {
      final output = Output.json(name: 'payload', description: 'Any JSON.');

      final format = await _responseFormat(output);
      expect(format, isA<provider.ResponseFormatJson>());
      expect((format as provider.ResponseFormatJson).schema, isNull);
      expect(format.name, 'payload');
      expect(format.description, 'Any JSON.');
      expect(
          await _complete(output, '[1,true,null]'), <Object?>[1, true, null]);
    });

    test('wraps complete parse failures in NoObjectGeneratedError', () {
      final output = Output.json();

      expect(
        () => output.parseCompleteOutput(OutputText('not json'), _context),
        throwsA(
          isA<NoObjectGeneratedError>()
              .having(
                (error) => error.message,
                'message',
                'No object generated: could not parse the response.',
              )
              .having((error) => error.cause, 'cause', isA<JsonParseError>())
              .having((error) => error.text, 'text', 'not json'),
        ),
      );
    });

    test('partial parse returns repaired arbitrary JSON', () async {
      final output = Output.json();

      expect(await _partial(output, '{"a":[1,2'), <String, Object?>{
        'a': <Object?>[1, 2],
      });
      expect(await _partial(output, 'not json'), isNull);
    });

    test('partial parse preserves a parsed JSON null', () async {
      final output = Output.json();

      final partial = output.parsePartialOutput('null');

      expect(partial, isNotNull);
      expect(partial!.partial, isNull);
    });
  });
}
