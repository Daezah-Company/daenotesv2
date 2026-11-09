import 'dart:convert';

import 'package:daenotes/data/api/api_client.dart';
import 'package:daenotes/data/api/token_storage.dart';
import 'package:daenotes/data/auth/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokenStorage extends TokenStorage {
  String? token = 'saved-token';
  String? user = jsonEncode({
    'token': 'saved-token',
    'user': {'id': 8, 'name': 'Cached name', 'email': 'cached@example.test'},
  });

  @override
  Future<String?> readToken() async => token;

  @override
  Future<String?> readUser() async => user;

  @override
  Future<void> writeToken(String value) async => token = value;

  @override
  Future<void> writeUser(String value) async => user = value;

  @override
  Future<void> clear() async {
    token = null;
    user = null;
  }
}

class _ReplyAdapter implements HttpClientAdapter {
  _ReplyAdapter(this.reply);

  final Future<ResponseBody> Function(RequestOptions) reply;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) => reply(options);

  @override
  void close({bool force = false}) {}
}

Dio _dioWith(Future<ResponseBody> Function(RequestOptions) reply) =>
    Dio(BaseOptions(baseUrl: 'https://api.example.test/api'))
      ..httpClientAdapter = _ReplyAdapter(reply);

ResponseBody _json(Object body, int status) => ResponseBody.fromString(
  jsonEncode(body),
  status,
  headers: const {
    Headers.contentTypeHeader: ['application/json; charset=utf-8'],
  },
);

void main() {
  test(
    'restore refreshes the cached profile before accepting the session',
    () async {
      final tokens = _MemoryTokenStorage();
      final api = ApiClient(
        tokens: tokens,
        dio: _dioWith(
          (_) async => _json({
            'data': {
              'id': 8,
              'name': 'Current name',
              'email': 'user@example.test',
            },
          }, 200),
        ),
      );

      final session = await AuthRepository(api, tokens).restore();

      expect(session?.token, 'saved-token');
      expect(session?.name, 'Current name');
      expect(session?.email, 'user@example.test');
      expect(jsonDecode(tokens.user!)['user']['name'], 'Current name');
    },
  );

  test('restore clears a revoked token before routing to login', () async {
    final tokens = _MemoryTokenStorage();
    final api = ApiClient(
      tokens: tokens,
      dio: _dioWith((_) async => _json({'message': 'Unauthenticated.'}, 401)),
    );

    expect(await AuthRepository(api, tokens).restore(), isNull);
    expect(tokens.token, isNull);
    expect(tokens.user, isNull);
  });

  test('restore keeps a cached session during a network outage', () async {
    final tokens = _MemoryTokenStorage();
    final api = ApiClient(
      tokens: tokens,
      dio: _dioWith((options) async {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionError,
        );
      }),
    );

    final session = await AuthRepository(api, tokens).restore();

    expect(session?.userId, 8);
    expect(session?.email, 'cached@example.test');
    expect(tokens.token, 'saved-token');
  });

  test(
    'restore rejects a token without a cached identity while offline',
    () async {
      final tokens = _MemoryTokenStorage()..user = null;
      final api = ApiClient(
        tokens: tokens,
        dio: _dioWith((options) async {
          throw DioException(
            requestOptions: options,
            type: DioExceptionType.connectionError,
          );
        }),
      );

      expect(await AuthRepository(api, tokens).restore(), isNull);
      // Leave the token intact so a later online attempt can still validate it.
      expect(tokens.token, 'saved-token');
    },
  );
}
