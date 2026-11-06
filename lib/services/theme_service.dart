import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists and exposes the user-selected [ThemeMode].
///
/// Uses SharedPreferences key `theme_mode` with values:
///   0 = system  |  1 = light  |  2 = dark
class ThemeService extends ChangeNotifier {
  static const _key = 'theme_mode';

  ThemeMode _mode = ThemeMode.light;

  ThemeMode get mode => _mode;

  bool get isDark => false;
  bool get isLight => true;
  bool get isSystem => false;

  /// Human-readable label for the current mode.
  String get label => 'Light';

  /// Load persisted preference on startup. (Now forced to Light)
  Future<void> init() async {
    _mode = ThemeMode.light;
    notifyListeners();
  }

  /// Change and persist theme mode. (Now forced to Light)
  Future<void> setMode(ThemeMode mode) async {
    _mode = ThemeMode.light;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_key, ThemeMode.values.indexOf(ThemeMode.light));
  }

  /// Convenience toggle between light and dark. (Now no-op/force light)
  Future<void> toggle() async {
    await setMode(ThemeMode.light);
  }
}
