import 'dart:convert';

import 'package:pigcode_ai_protocol_utils/pigcode_ai_protocol_utils.dart';
import 'package:test/test.dart';

void main() {
  const codec = JsonRpcCodec();

  group('JSON-RPC 2.0 codec', () {
    test('round-trips a request and preserves unknown fields', () {
      final message = codec.decode(
        '{"jsonrpc":"2.0","id":"req-1","method":"tools/list",'
        '"params":{"cursor":"opaque"},"trace":{"sampled":true}}',
      );

      expect(message, isA<JsonRpcRequest>());
      final request = message as JsonRpcRequest;
      expect(request.id, JsonRpcStringId('req-1'));
      expect(request.method, 'tools/list');
      expect(request.params, <String, Object?>{'cursor': 'opaque'});
      expect(request.extensions, <String, Object?>{
        'trace': <String, Object?>{'sampled': true},
      });
      expect(
        () => (request.extensions['trace']! as Map<String, Object?>)['x'] = 1,
        throwsUnsupportedError,
      );
      expect(codec.decode(codec.encode(request)).toJson(), request.toJson());
    });

    test('round-trips notification, success, and error envelopes', () {
      final notification = codec.decode(
        '{"jsonrpc":"2.0","method":"notifications/progress",'
        '"params":[1,2]}',
      );
      final success = codec.decode(
        '{"jsonrpc":"2.0","id":7,"result":null,"future":"kept"}',
      );
      final error = codec.decode(
        '{"jsonrpc":"2.0","id":null,"error":'
        '{"code":-32600,"message":"Invalid Request","data":null,'
        '"retryable":false}}',
      );

      expect(notification, isA<JsonRpcNotification>());
      expect(success, isA<JsonRpcSuccessResponse>());
      expect((success as JsonRpcSuccessResponse).result, isNull);
      expect(success.extensions, <String, Object?>{'future': 'kept'});
      expect(error, isA<JsonRpcErrorResponse>());
      final response = error as JsonRpcErrorResponse;
      expect(response.id, const JsonRpcNullId());
      expect(response.error.code, -32600);
      expect(response.error.message, 'Invalid Request');
      expect(response.error.hasData, isTrue);
      expect(response.error.data, isNull);
      expect(response.error.extensions, <String, Object?>{
        'retryable': false,
      });

      for (final message in <JsonRpcMessage>[
        notification,
        success,
        error,
      ]) {
        expect(codec.decode(codec.encode(message)).toJson(), message.toJson());
      }
    });

    test('accepts string and safe integer IDs and rejects invalid IDs', () {
      expect(JsonRpcId.fromJson('opaque'), JsonRpcStringId('opaque'));
      expect(JsonRpcId.fromJson(42), JsonRpcIntegerId(42));
      expect(JsonRpcId.fromJson(null), const JsonRpcNullId());

      for (final value in <Object?>[
        true,
        '',
        1.5,
        9007199254740992,
        <String, Object?>{},
      ]) {
        expect(
          () => JsonRpcId.fromJson(value),
          throwsA(
            isA<JsonRpcException>().having(
              (error) => error.code,
              'code',
              'json_rpc_invalid_id',
            ),
          ),
        );
      }
    });

    test('allows null only for error responses', () {
      expect(
        () => codec.decode(
          '{"jsonrpc":"2.0","id":null,"method":"x"}',
        ),
        throwsA(
          isA<JsonRpcException>().having(
            (error) => error.code,
            'code',
            'json_rpc_invalid_id',
          ),
        ),
      );
      expect(
        () => codec.decode(
          '{"jsonrpc":"2.0","id":null,"result":true}',
        ),
        throwsA(
          isA<JsonRpcException>().having(
            (error) => error.code,
            'code',
            'json_rpc_invalid_id',
          ),
        ),
      );
      expect(
        codec.decode(
          '{"jsonrpc":"2.0","id":null,"error":'
          '{"code":-32600,"message":"Invalid Request"}}',
        ),
        isA<JsonRpcErrorResponse>(),
      );
    });

    test('rejects duplicate keys at any object depth', () {
      for (final source in <String>[
        '{"jsonrpc":"2.0","id":1,"id":2,"method":"x"}',
        '{"jsonrpc":"2.0","id":1,"method":"x",'
            '"params":{"name":1,"n\\u0061me":2}}',
      ]) {
        expect(
          () => codec.decode(source),
          throwsA(
            isA<JsonRpcException>().having(
              (error) => error.code,
              'code',
              'json_rpc_duplicate_key',
            ),
          ),
        );
      }
    });

    test('uses deterministic recursive object key order', () {
      final first = JsonRpcRequest(
        id: JsonRpcStringId('id'),
        method: 'x',
        params: <String, Object?>{
          'z': 1,
          'a': <String, Object?>{'d': 4, 'b': 2},
        },
      );
      final second = JsonRpcRequest(
        id: JsonRpcStringId('id'),
        method: 'x',
        params: <String, Object?>{
          'a': <String, Object?>{'b': 2, 'd': 4},
          'z': 1,
        },
      );

      expect(codec.encode(first), codec.encode(second));
    });

    test('rejects invalid envelope shapes with stable codes', () {
      final cases = <String, String>{
        '{"jsonrpc":"1.0","id":1,"method":"x"}': 'json_rpc_invalid_version',
        '{"jsonrpc":"2.0","id":true,"method":"x"}': 'json_rpc_invalid_id',
        '{"jsonrpc":"2.0","id":1,"result":1,"error":'
            '{"code":-1,"message":"x"}}': 'json_rpc_ambiguous_response',
        '{"jsonrpc":"2.0","id":1}': 'json_rpc_invalid_envelope',
        '{"jsonrpc":"2.0","method":"x","params":1}': 'json_rpc_invalid_params',
        '[]': 'json_rpc_batch_unsupported',
      };

      for (final entry in cases.entries) {
        expect(
          () => codec.decode(entry.key),
          throwsA(
            isA<JsonRpcException>().having(
              (error) => error.code,
              'code',
              entry.value,
            ),
          ),
          reason: entry.key,
        );
      }
    });

    test('rejects malformed JSON and invalid UTF-8-neutral values', () {
      expect(
        () => codec.decode('{'),
        throwsA(
          isA<JsonRpcException>().having(
            (error) => error.code,
            'code',
            'json_rpc_malformed_json',
          ),
        ),
      );
      expect(
        () => codec.decodeValue(<String, Object?>{
          'jsonrpc': '2.0',
          'method': 'x',
          'extra': double.nan,
        }),
        throwsA(
          isA<JsonRpcException>().having(
            (error) => error.code,
            'code',
            'json_rpc_invalid_json_value',
          ),
        ),
      );
    });

    test('encoded envelope is valid JSON', () {
      final message = JsonRpcSuccessResponse(
        id: JsonRpcIntegerId(9),
        result: <String, Object?>{'ok': true},
      );

      expect(
        jsonDecode(codec.encode(message)),
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 9,
          'result': <String, Object?>{'ok': true},
        },
      );
    });
  });
}
