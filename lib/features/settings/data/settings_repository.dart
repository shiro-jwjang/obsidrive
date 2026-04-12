import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

final themeModeControllerProvider =
    StateNotifierProvider<ThemeModeController, ThemeMode>((ref) {
      final controller = ThemeModeController(
        ref.watch(settingsRepositoryProvider),
      );
      controller.load();
      return controller;
    });

class SettingsRepository {
  SettingsRepository({SharedPreferences? preferences})
    : _preferences = preferences;

  static const _themeModeKey = 'settings.themeMode';

  final SharedPreferences? _preferences;

  Future<ThemeMode> getThemeMode() async {
    final preferences = await _getPreferences();
    return _themeModeFromString(preferences.getString(_themeModeKey));
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    final preferences = await _getPreferences();
    await preferences.setString(_themeModeKey, mode.name);
  }

  Future<SharedPreferences> _getPreferences() async {
    return _preferences ?? SharedPreferences.getInstance();
  }

  ThemeMode _themeModeFromString(String? value) {
    return switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }
}

class ThemeModeController extends StateNotifier<ThemeMode> {
  ThemeModeController(this._repository) : super(ThemeMode.system);

  final SettingsRepository _repository;

  Future<void> load() async {
    state = await _repository.getThemeMode();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    state = mode;
    await _repository.setThemeMode(mode);
  }
}
