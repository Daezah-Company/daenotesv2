import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import '../db/meta_dao.dart';
import '../providers.dart';

@immutable
class AppPreferences {
  const AppPreferences({
    this.themeMode = ThemeMode.dark,
    this.haptics = true,
    this.uiSounds = true,
  });

  final ThemeMode themeMode;
  final bool haptics;
  final bool uiSounds;

  AppPreferences copyWith({
    ThemeMode? themeMode,
    bool? haptics,
    bool? uiSounds,
  }) => AppPreferences(
    themeMode: themeMode ?? this.themeMode,
    haptics: haptics ?? this.haptics,
    uiSounds: uiSounds ?? this.uiSounds,
  );
}

final appPreferencesProvider =
    NotifierProvider<AppPreferencesController, AppPreferences>(
      AppPreferencesController.new,
    );

class AppPreferencesController extends Notifier<AppPreferences> {
  static const _themeKey = 'preference.themeMode';
  static const _hapticsKey = 'preference.haptics';
  static const _soundsKey = 'preference.uiSounds';
  int _loadEpoch = 0;

  @override
  AppPreferences build() {
    final db = ref.watch(databaseProvider);
    unawaited(_load(db, ++_loadEpoch));
    return const AppPreferences();
  }

  Future<void> _load(AppDatabase db, int epoch) async {
    final values = await Future.wait([
      db.metaGet(_themeKey),
      db.metaGet(_hapticsKey),
      db.metaGet(_soundsKey),
    ]);
    if (!ref.mounted || epoch != _loadEpoch) return;
    state = AppPreferences(
      themeMode: switch (values[0]) {
        'light' => ThemeMode.light,
        'system' => ThemeMode.system,
        _ => ThemeMode.dark,
      },
      haptics: values[1] != 'false',
      uiSounds: values[2] != 'false',
    );
  }

  Future<void> setThemeMode(ThemeMode value) async {
    state = state.copyWith(themeMode: value);
    await ref.read(databaseProvider).metaSet(_themeKey, switch (value) {
      ThemeMode.light => 'light',
      ThemeMode.system => 'system',
      ThemeMode.dark => 'dark',
    });
  }

  Future<void> setHaptics(bool value) async {
    state = state.copyWith(haptics: value);
    await ref.read(databaseProvider).metaSet(_hapticsKey, '$value');
  }

  Future<void> setUiSounds(bool value) async {
    state = state.copyWith(uiSounds: value);
    await ref.read(databaseProvider).metaSet(_soundsKey, '$value');
  }

  Future<void> tapFeedback() async {
    if (state.haptics) await HapticFeedback.selectionClick();
    if (state.uiSounds) await SystemSound.play(SystemSoundType.click);
  }
}
