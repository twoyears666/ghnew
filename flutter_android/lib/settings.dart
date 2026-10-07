import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'accelerator.dart';

/// Global in-app settings (dark mode + language + acceleration). Mirrors Swift
/// AppSettings. Exposed as a singleton so plain getters can read it;
/// notifyListeners drives UI rebuilds (the whole MaterialApp is wrapped in a
/// ListenableBuilder).
class SettingsStore extends ChangeNotifier {
  SettingsStore._();
  static final SettingsStore i = SettingsStore._();

  static const _darkKey = 'ghSettings.dark';
  static const _langKey = 'ghSettings.lang';
  static const _relayKey = 'ghSettings.accel.relay.enabled';
  static const _relayNodeKey = 'ghSettings.accel.relay.node';
  static const _relayArtifactsKey = 'ghSettings.accel.relay.artifacts';
  static const _concKey = 'ghSettings.accel.conc.enabled';
  static const _concLevelKey = 'ghSettings.accel.conc.level';
  static const _concArtifactsKey = 'ghSettings.accel.conc.artifacts';
  static const _autoUnzipKey = 'ghSettings.download.autoUnzip';

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

  // ============================ Acceleration ============================

  bool _relayEnabled = false;
  bool get relayEnabled => _relayEnabled;
  set relayEnabled(bool v) {
    if (_relayEnabled == v) return;
    _relayEnabled = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_relayKey, v));
    notifyListeners();
  }

  String _relayNode = Accelerator.defaultNodeHost;
  String get relayNode => _relayNode;
  set relayNode(String v) {
    if (_relayNode == v) return;
    _relayNode = v;
    SharedPreferences.getInstance().then((p) => p.setString(_relayNodeKey, v));
    notifyListeners();
  }

  /// 中转是否作用于 Actions 产物（风险项，默认关）
  bool _relayArtifacts = false;
  bool get relayArtifacts => _relayArtifacts;
  set relayArtifacts(bool v) {
    if (_relayArtifacts == v) return;
    _relayArtifacts = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_relayArtifactsKey, v));
    notifyListeners();
  }

  bool _concEnabled = false;
  bool get concEnabled => _concEnabled;
  set concEnabled(bool v) {
    if (_concEnabled == v) return;
    _concEnabled = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_concKey, v));
    notifyListeners();
  }

  int _concLevel = 2;
  int get concLevel => _concLevel;
  set concLevel(int v) {
    if (_concLevel == v) return;
    _concLevel = v;
    SharedPreferences.getInstance().then((p) => p.setInt(_concLevelKey, v));
    notifyListeners();
  }

  /// 并发是否作用于 Actions 产物（风险项，默认关）
  bool _concArtifacts = false;
  bool get concArtifacts => _concArtifacts;
  set concArtifacts(bool v) {
    if (_concArtifacts == v) return;
    _concArtifacts = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_concArtifactsKey, v));
    notifyListeners();
  }

  // ============================ Downloads ============================

  /// Actions 产物下载后自动解压（默认开）
  bool _autoUnzipArtifacts = true;
  bool get autoUnzipArtifacts => _autoUnzipArtifacts;
  set autoUnzipArtifacts(bool v) {
    if (_autoUnzipArtifacts == v) return;
    _autoUnzipArtifacts = v;
    SharedPreferences.getInstance().then((p) => p.setBool(_autoUnzipKey, v));
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

    _relayEnabled = p.getBool(_relayKey) ?? false;
    final node = p.getString(_relayNodeKey);
    _relayNode =
        (node == null || node.isEmpty) ? Accelerator.defaultNodeHost : node;
    _relayArtifacts = p.getBool(_relayArtifactsKey) ?? false;
    _concEnabled = p.getBool(_concKey) ?? false;
    final level = p.getInt(_concLevelKey);
    _concLevel = (level == null || level == 0) ? 2 : level;
    _concArtifacts = p.getBool(_concArtifactsKey) ?? false;
    _autoUnzipArtifacts = p.getBool(_autoUnzipKey) ?? true;
  }
}