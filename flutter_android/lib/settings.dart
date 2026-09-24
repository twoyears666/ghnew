import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global in-app settings (dark mode + language). Mirrors Swift AppSettings.
/// Exposed as a singleton so plain getters can read it; notifyListeners drives
/// UI rebuilds (the whole MaterialApp is wrapped in a ListenableBuilder).
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore i = SettingsStore._();

  static const _darkKey = 'ghSettings.dark';
  static const _langKey = 'ghSettings.lang';

  bool _isDark = false;
  bool get isDark => _isDark;
  set isDark(bool v) {
    if (_isDark == v) return;
    _isDark = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_darkKey, v));
    notifyListeners();
  }

  String _lang = 'en'; // 'zh' | 'en'
  String get lang => _lang;
  bool get isZh => _lang == 'zh';
  set lang(String v) {
    if (_lang == v) return;
    _lang = v;
    SharedPreferences.getInstance().then((p) => p.setString(_langKey, v));
    notifyListeners();
  }

  /// Load persisted settings; default language follows the device locale.
  Future<void> init() async {
    final p = await SharedPreferences.getInstance();
    _isDark = p.getBool(_darkKey) ?? false;
    final saved = p.getString(_langKey);
    if (saved != null) {
      _lang = saved;
    } else {
      final code =
          PlatformDispatcher.instance.locale.languageCode.toLowerCase();
      _lang = (code == 'zh' || code == 'zh-cn') ? 'zh' : 'en';
    }
  }
}