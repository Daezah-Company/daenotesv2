import 'dart:convert';

import 'package:dio/dio.dart';

import '../api/api_client.dart';
import '../api/token_storage.dart';

/// Auth operations over the Sanctum endpoints (contract §4). The login and
/// register *screens* belong to feature agents; they call these methods
/// through `authControllerProvider`.
class AuthRepository {
  AuthRepository(this._api, this._tokens);

  final ApiClient _api;
  final TokenStorage _tokens;

  /// Rehydrate a stored session on app start. No network required — a stale
  /// token used to be trusted here until the first background request. That
  /// made the inbox flash before the interceptor sent the user back to login.
  /// Validate it before the router exposes authenticated routes. If the API is
  /// unreachable, keep a complete cached session so offline use still works.
  Future<AuthSession?> restore() async {
    final token = await _tokens.readToken();
    if (token == null || token.isEmpty) return null;
    final userJson = await _tokens.readUser();
    AuthSession? cached;
    try {
      if (userJson != null) {
        final session = AuthSession.fromJson(
          jsonDecode(userJson) as Map<String, dynamic>,
        );
        if (session.userId > 0 && session.email.isNotEmpty) {
          cached = AuthSession(
            token: token,
            userId: session.userId,
            name: session.name,
            email: session.email,
          );
        }
      }
    } on Object {
      // A malformed cached profile must not be treated as a valid identity.
    }

    try {
      final user = await _api.me();
      final session = AuthSession(
        token: token,
        userId: (user['id'] as num?)?.toInt() ?? 0,
        name: user['name'] as String? ?? '',
        email: user['email'] as String? ?? '',
      );
      if (session.userId <= 0 || session.email.isEmpty) {
        throw const FormatException('Invalid user session response.');
      }
      await _bindLegacyDatabase(session);
      await _tokens.writeUser(jsonEncode(session.toJson()));
      return session;
    } on DioException catch (error) {
      if (error.response?.statusCode == 401) {
        await _tokens.clear();
        return null;
      }
      // Keep the user in the app during an outage; the cached bearer token
      // will be checked again by the next authenticated request.
      return _offlineSession(token, cached);
    } on FormatException {
      return _offlineSession(token, cached);
    } on Object {
      return _offlineSession(token, cached);
    }
  }

  Future<AuthSession> login(String email, String password) => _run(() async {
    final session = await _api.login(email, password);
    return _persist(session);
  });

  Future<AuthSession> register(String name, String email, String password) =>
      _run(() async {
        final session = await _api.register(name, email, password);
        return _persist(session);
      });

  /// Runs an auth action, normalising Dio failures into [ApiError] so login
  /// screens can show `errors` / `message` straight from the contract shape.
  Future<AuthSession> _run(Future<AuthSession> Function() action) async {
    try {
      return await action();
    } on ApiError {
      rethrow;
    } on Object catch (e) {
      throw apiErrorFrom(e);
    }
  }

  Future<void> logout() async {
    try {
      await _api.logout();
    } on Object catch (_) {
      // Logging out offline still clears the local session.
    }
    await _tokens.clear();
  }

  Future<AuthSession> _persist(AuthSession session) async {
    await _bindLegacyDatabase(session);
    // Write the profile first. The token is the session commit marker, so a
    // process death cannot leave a bearer token paired with an absent profile.
    await _tokens.writeUser(jsonEncode(session.toJson()));
    await _tokens.writeToken(session.token);
    return session;
  }

  Future<AuthSession?> _offlineSession(
    String token,
    AuthSession? cached,
  ) async {
    // A token without a complete cached identity can happen after an old or
    // interrupted upgrade. Do not expose protected routes with userId=0: the
    // first sync request would then fail and send the user straight back out.
    if (cached == null) return null;
    final session = AuthSession(
      token: token,
      userId: cached.userId,
      name: cached.name,
      email: cached.email,
    );
    await _bindLegacyDatabase(session);
    return session;
  }

  Future<void> _bindLegacyDatabase(AuthSession session) async {
    if (session.userId <= 0) return;
    try {
      await _tokens.bindLegacyDatabaseOwner(session.userId);
    } on Object {
      // A storage failure must not turn a valid API login into an auth error.
    }
  }

  /// Wire error message out of a DioException-shaped error.
  static String describeError(Object error) {
    if (error is ApiError) return error.message;
    return 'Something went wrong. Please try again.';
  }
}

/// Typed API failure carrying the server `{"message": ...}` (contract §4).
class ApiError implements Exception {
  ApiError(this.message, {this.statusCode, this.fieldErrors = const {}});

  final String message;
  final int? statusCode;
  final Map<String, List<String>> fieldErrors;

  @override
  String toString() => 'ApiError($statusCode): $message';
}

/// Maps DioException payloads to [ApiError]. Lives here so both feature and
/// foundation code surface identical messages.
ApiError apiErrorFrom(Object error) {
  final e = error;
  final data = e is DioException ? e.response?.data : null;
  if (data is Map) {
    final message = data['message'] as String? ?? 'Request failed';
    final errors = <String, List<String>>{};
    final raw = data['errors'];
    if (raw is Map) {
      raw.forEach((k, v) {
        errors['$k'] = v is List ? v.map((e) => '$e').toList() : ['$v'];
      });
    }
    return ApiError(
      message,
      statusCode: e is DioException ? e.response?.statusCode : null,
      fieldErrors: errors,
    );
  }
  if (e is DioException) {
    return ApiError(
      e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.receiveTimeout
          ? 'The server took too long to respond.'
          : 'Network error. Check your connection.',
      statusCode: e.response?.statusCode,
    );
  }
  return ApiError('$e');
}
