import 'dart:async';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Local (offline) notifications. No internet or Firebase needed.
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final StreamController<String> _taps = StreamController<String>.broadcast();

  /// Emits the report id when the user taps a notification while the app is running.
  Stream<String> get taps => _taps.stream;

  /// Report id if the app was launched by tapping a notification.
  String? launchPayload;

  bool _ready = false;

  static const AndroidNotificationDetails _normal = AndroidNotificationDetails(
    'triage_updates',
    'Report updates',
    channelDescription: 'Your report was triaged by the AI',
    importance: Importance.defaultImportance,
    priority: Priority.defaultPriority,
  );

  static const AndroidNotificationDetails _critical = AndroidNotificationDetails(
    'triage_critical',
    'Critical reports',
    channelDescription: 'Severity 4 and 5 triage results',
    importance: Importance.max,
    priority: Priority.high,
  );

  Future<void> init() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      );
      await _plugin.initialize(
        settings,
        onDidReceiveNotificationResponse: (r) {
          final p = r.payload;
          if (p != null && p.isNotEmpty) _taps.add(p);
        },
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.requestNotificationsPermission(); // Android 13+ asks the user
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp ?? false) {
        launchPayload = launch!.notificationResponse?.payload;
      }
      _ready = true;
    } catch (_) {
      _ready = false; // the app must still work without notifications
    }
  }

  Future<void> showTriaged({
    required String reportId,
    required int severity,
    required String category,
    required String summary,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(
        reportId.hashCode & 0x7fffffff,
        'Report triaged: severity $severity, $category',
        summary,
        NotificationDetails(android: severity >= 4 ? _critical : _normal),
        payload: reportId,
      );
    } catch (_) {}
  }
}