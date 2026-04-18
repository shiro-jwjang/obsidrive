import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidrive/features/settings/data/settings_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  test('getThemeMode defaults to system when no preference exists', () async {
    final repository = SettingsRepository();

    final mode = await repository.getThemeMode();

    expect(mode, ThemeMode.system);
  });

  test('setThemeMode persists selected theme mode', () async {
    final repository = SettingsRepository();

    await repository.setThemeMode(ThemeMode.dark);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.themeMode'), 'dark');
    expect(await repository.getThemeMode(), ThemeMode.dark);
  });

  test('invalid stored theme mode falls back to system', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'settings.themeMode': 'unknown',
    });
    final repository = SettingsRepository();

    final mode = await repository.getThemeMode();

    expect(mode, ThemeMode.system);
  });
}
