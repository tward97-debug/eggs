import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../game/engine.dart';

/// Phone alerts for when crops ripen and when they are about to wither.
class GardenNotifications {
  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _initialized = false;

  /// Replaces every scheduled alert with ones matching the current garden.
  /// Alerts are best-effort and can never break the game. Returns a message
  /// for the player when alerts cannot work, otherwise null.
  static Future<String?> sync(
    GameEngine engine, {
    bool askPermission = false,
  }) async {
    try {
      if (!_initialized) {
        await _plugin.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_notification_egg'),
          ),
        );
        _initialized = true;
      }
      if (askPermission) {
        final granted = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.requestNotificationsPermission();
        if (granted == false) {
          return 'Garden alerts are off. Allow notifications for '
              'Chickenville in your phone settings to get them.';
        }
      }
      await _plugin.cancelAll();
      final now = DateTime.now().millisecondsSinceEpoch;
      var id = 0;
      for (final alert in gardenAlerts(engine)) {
        if (alert.atMs <= now) {
          continue;
        }
        await _plugin.zonedSchedule(
          id: id++,
          title: alert.title,
          body: alert.body,
          scheduledDate: tz.TZDateTime.fromMillisecondsSinceEpoch(
            tz.UTC,
            alert.atMs,
          ),
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'garden',
              'Garden',
              channelDescription: 'Crops ready to harvest or about to wither',
            ),
          ),
          // shortcut: inexact alarms can arrive several minutes late; switch
          // to exact alarms (needs an extra Android permission) if that hurts.
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
      return null;
    } on PlatformException catch (error) {
      return 'Garden alerts are not working: ${error.message ?? error.code}';
    } catch (_) {
      // No notification plugin here (tests, unsupported platforms).
      return null;
    }
  }
}

typedef GardenAlert = ({int atMs, String title, String body});

/// One "ready" and one "about to wither" alert per batch of crops that ripen
/// in the same minute.
List<GardenAlert> gardenAlerts(GameEngine engine) {
  final garden = engine.data.garden;
  final batches = <int, int>{};
  for (final planted in engine.state.garden.planted.values) {
    final minute = engine.cropReadyAtMs(planted) ~/ 60000;
    batches[minute] = (batches[minute] ?? 0) + 1;
  }
  final warningMinutes = garden.witherWarningMinutes.round();
  return [
    for (final MapEntry(key: minute, value: count) in batches.entries) ...[
      (
        atMs: minute * 60000,
        title: 'Your garden is ready',
        body: '$count ${count == 1 ? 'crop is' : 'crops are'} ready to '
            'harvest.',
      ),
      (
        atMs: (minute + garden.witherMinutes.round() - warningMinutes) * 60000,
        title: 'Crops about to wither',
        body: 'Harvest within $warningMinutes minutes or lose '
            '${count == 1 ? 'it' : 'them'}.',
      ),
    ],
  ];
}
