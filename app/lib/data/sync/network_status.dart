import 'dart:async';

import 'package:flutter/foundation.dart';

/// Offline-aware connectivity signal. The app pushes reachability changes in
/// via [setOnline]; SyncEngine checks [isOnline] before every attempt and
/// backs off exponentially on failure.
class NetworkStatus extends ChangeNotifier {
  NetworkStatus({bool initialOnline = true}) : _online = initialOnline;

  bool _online;
  final _changes = StreamController<bool>.broadcast();

  bool get isOnline => _online;

  /// Broadcast stream of online/offline transitions.
  Stream<bool> get changes => _changes.stream;

  void setOnline(bool value) {
    if (value == _online) return;
    _online = value;
    _changes.add(value);
    notifyListeners();
  }

  @override
  void dispose() {
    _changes.close();
    super.dispose();
  }
}

/// Exponential backoff schedule: base * 2^attempt, capped, deterministic
/// (no jitter — tests rely on the exact sequence).
Duration backoffDelay(
  int attempt, {
  Duration base = const Duration(seconds: 2),
  Duration max = const Duration(minutes: 2),
}) {
  final clamped = attempt.clamp(0, 16);
  final scaled = base.inMilliseconds << clamped;
  if (scaled <= 0 || scaled > max.inMilliseconds) return max;
  return Duration(milliseconds: scaled);
}
