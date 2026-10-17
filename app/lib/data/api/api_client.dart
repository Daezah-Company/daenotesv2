import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'token_storage.dart';

/// Dio wrapper for the DaeNotes API (docs/CONTRACT.md §4). All responses are
/// unwrapped from `{"data": ...}` here so callers see plain maps/lists.
class ApiClient {
  ApiClient({
    required this.tokens,
    String? baseUrl,
    VoidCallback? onUnauthorized,
    Dio? dio,
  }) : dio =
           dio ??
           Dio(
             BaseOptions(
               baseUrl: baseUrl ?? defaultBaseUrl,
               connectTimeout: const Duration(seconds: 10),
               receiveTimeout: const Duration(seconds: 20),
               contentType: Headers.jsonContentType,
             ),
           ) {
    this.dio.interceptors.add(_BearerInterceptor(tokens, onUnauthorized));
  }

  /// Override with `--dart-define=DAENOTES_API_URL=https://…`.
  static const String defaultBaseUrl = String.fromEnvironment(
    'DAENOTES_API_URL',
    defaultValue: 'http://localhost:8000/api',
  );

  final Dio dio;
  final TokenStorage tokens;

  // ---------------------------------------------------------------- auth

  Future<AuthSession> register(String name, String email, String password) =>
      _authPost('/auth/register', {
        'name': name,
        'email': email,
        'password': password,
      });

  Future<AuthSession> login(String email, String password) =>
      _authPost('/auth/login', {'email': email, 'password': password});

  Future<void> logout() => dio.post('/auth/logout');

  Future<Map<String, dynamic>> me() async {
    final data = _data(await dio.get('/auth/me'));
    return (data as Map).cast<String, dynamic>();
  }

  Future<AuthSession> _authPost(String path, Map<String, dynamic> body) async {
    final resp = await dio.post(path, data: body);
    final data = _data(resp) as Map;
    return AuthSession.fromJson(data.cast<String, dynamic>());
  }

  // ---------------------------------------------------------------- sync

  /// GET /api/sync/changes?since=ISO8601 — raw `data` map
  /// ({notes, todos, links, reminders, deleted, server_time}).
  Future<Map<String, dynamic>> syncChanges(DateTime? since) async {
    final resp = await dio.get(
      '/sync/changes',
      queryParameters: {
        if (since != null) 'since': since.toUtc().toIso8601String(),
      },
    );
    return (_data(resp) as Map).cast<String, dynamic>();
  }

  /// POST /api/sync/push — raw `data` map
  /// ({accepted, conflicts, server_time}).
  Future<Map<String, dynamic>> syncPush(Map<String, dynamic> payload) async {
    final resp = await dio.post('/sync/push', data: payload);
    return (_data(resp) as Map).cast<String, dynamic>();
  }

  // --------------------------------------------------------------- graph

  /// GET /api/graph?depth=1|2&types=note,todo -> {nodes:[], edges:[]}
  Future<Map<String, dynamic>> graph({
    int depth = 1,
    List<String>? types,
  }) async {
    final resp = await dio.get(
      '/graph',
      queryParameters: {
        'depth': depth,
        if (types != null && types.isNotEmpty) 'types': types.join(','),
      },
    );
    return (_data(resp) as Map).cast<String, dynamic>();
  }

  // ---------------------------------------------------------------- util

  static Object? _data(Response resp) {
    final body = resp.data;
    if (body is Map && body.containsKey('data')) return body['data'];
    return body;
  }
}

/// A signed-in session as returned by /auth/login and /auth/register.
class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.name,
    required this.email,
  });

  final String token;
  final int userId;
  final String name;
  final String email;

  factory AuthSession.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?)?.cast<String, dynamic>() ?? const {};
    return AuthSession(
      token: json['token'] as String,
      userId: (user['id'] as num?)?.toInt() ?? 0,
      name: user['name'] as String? ?? '',
      email: user['email'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'token': token,
    'user': {'id': userId, 'name': name, 'email': email},
  };
}

class _BearerInterceptor extends Interceptor {
  _BearerInterceptor(this.tokens, this.onUnauthorized);

  final TokenStorage tokens;
  final VoidCallback? onUnauthorized;

  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final token = await tokens.readToken();
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Expired/invalid token: drop it and push the app back to login.
      tokens.clear();
      onUnauthorized?.call();
    }
    handler.next(err);
  }
}
