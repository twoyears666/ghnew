import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local notification bridge for the desktop/mobile Flutter ports
/// (Android + Windows). Mirrors the Swift side's UNUserNotificationCenter
/// alerts: a workflow run posts one banner when it starts and one when it
/// concludes.
///
/// Every call is best-effort: on a platform without an implementation (or when
/// the user denies the permission) the bridge degrades to a silent no-op rather
/// than throwing a MissingPluginException.
class Alerts {
  Alerts._();
  static final Alerts i = Alerts._();

  static const _channelId = 'ghnew_action_runs';
  static const _channelName = 'Action runs';
  static const _channelDescription = 'Started and finished action runs';

  /// Stable identity for Windows toast activation (must never change).
  static const _windowsGuid = '1f0e6b4a-9c37-4d52-8a71-6b2e9d4c0f83';

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Prepare the plugin and ask for the notification permission where the OS
  /// requires one (Android 13+).
  Future<void> init() async {
    try {
      final settings = _initializationSettings();
      if (settings == null) return; // no implementation on this platform
      await _plugin.initialize(settings: settings);
      // The Android channel is created implicitly by the first show(); all we
      // need up front is the runtime permission.
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  InitializationSettings? _initializationSettings() {
    if (Platform.isAndroid) {
      return const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
    }
    if (Platform.isWindows) {
      return const InitializationSettings(
        windows: WindowsInitializationSettings(
          appName: 'ghnew',
          appUserModelId: 'com.twoyears666.ghnew',
          guid: _windowsGuid,
        ),
      );
    }
    return null;
  }

  /// Show one banner. `identifier` is the caller's stable message id, so a
  /// given run start/end can never be announced twice.
  Future<void> show({
    required String identifier,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        id: identifier.hashCode & 0x7fffffff,
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: const AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          windows: WindowsNotificationDetails(),
        ),
      );
    } catch (_) {}
  }
}
