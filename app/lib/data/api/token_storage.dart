import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bearer-token persistence. Wraps flutter_secure_storage; the in-memory
/// copy keeps the Dio interceptor synchronous-ish and lets tests inject a
/// fake by constructing with a [FlutterSecureStorage] stub or [seed].
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'daenotes.token';
  static const _userKey = 'daenotes.user';

  final FlutterSecureStorage _storage;

  String? _cachedToken;

  String? get cachedToken => _cachedToken;

  Future<String?> readToken() async =>
      _cachedToken ??= await _storage.read(key: _tokenKey);

  Future<void> writeToken(String token) async {
    _cachedToken = token;
    await _storage.write(key: _tokenKey, value: token);
  }

  Future<void> writeUser(String userJson) =>
      _storage.write(key: _userKey, value: userJson);

  Future<String?> readUser() => _storage.read(key: _userKey);

  Future<void> clear() async {
    _cachedToken = null;
    await _storage.delete(key: _tokenKey);
    await _storage.delete(key: _userKey);
  }
}
