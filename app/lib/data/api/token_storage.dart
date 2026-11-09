import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bearer-token persistence. Wraps flutter_secure_storage; the in-memory
/// copy keeps the Dio interceptor synchronous-ish and lets tests inject a
/// fake by constructing with a [FlutterSecureStorage] stub or [seed].
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const _tokenKey = 'daenotes.token';
  static const _userKey = 'daenotes.user';
  static const _legacyDatabaseOwnerKey = 'daenotes.database_owner';

  final FlutterSecureStorage _storage;

  String? _cachedToken;
  int? _cachedLegacyDatabaseOwnerId;

  String? get cachedToken => _cachedToken;
  int? get legacyDatabaseOwnerId => _cachedLegacyDatabaseOwnerId;

  Future<void> bindLegacyDatabaseOwner(int userId) async {
    if (userId <= 0 || _cachedLegacyDatabaseOwnerId != null) return;
    final stored = await _storage.read(key: _legacyDatabaseOwnerKey);
    final parsed = int.tryParse(stored ?? '');
    if (parsed != null && parsed > 0) {
      _cachedLegacyDatabaseOwnerId = parsed;
      return;
    }
    // Existing installs keep using their original `daenotes` file for the
    // first account that successfully signs in after the upgrade.
    _cachedLegacyDatabaseOwnerId = userId;
    await _storage.write(key: _legacyDatabaseOwnerKey, value: '$userId');
  }

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
