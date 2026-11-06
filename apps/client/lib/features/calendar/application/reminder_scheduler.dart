import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../../tasks/domain/task.dart';
import '../domain/task_reminder.dart';

abstract interface class ReminderScheduler {
  Future<void> initialize();

  Future<bool> requestPermission();

  Future<void> schedule({required TaskReminder reminder, required Task task});

  Future<void> cancel(String reminderId);

  Future<void> cancelAll();
}

/// Системные локальные уведомления. Время хранится в UTC,
/// а планируется в локальной IANA-зоне устройства.
class LocalReminderScheduler implements ReminderScheduler {
  LocalReminderScheduler({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  bool _timezoneReady = false;

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }
    if (!_timezoneReady) {
      tzdata.initializeTimeZones();
      try {
        final zone = await FlutterTimezone.getLocalTimezone();
        tz.setLocalLocation(tz.getLocation(zone.identifier));
      } on Object {
        // Если системную зону получить не удалось, остаёмся в UTC.
      }
      _timezoneReady = true;
    }

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestSoundPermission: false,
          requestBadgePermission: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Ежедневник',
          appUserModelId: 'Georgiadivs.Zadachnik.Client.1',
          guid: 'e7d3c1a9-5b7a-4c9e-9f4e-2f6b8a1c0d33',
        ),
      ),
    );
    _initialized = true;
  }

  @override
  Future<void> initialize() => _ensureInitialized();

  @override
  Future<bool> requestPermission() async {
    try {
      await _ensureInitialized();
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >();
          final allowed =
              await android?.requestNotificationsPermission() ?? true;
          final exact = await android?.canScheduleExactNotifications() ?? false;
          if (!exact) {
            await android?.requestExactAlarmsPermission();
          }
          return allowed;
        case TargetPlatform.iOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    IOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(
                    alert: true,
                    sound: true,
                    badge: false,
                  ) ??
              false;
        case TargetPlatform.macOS:
          return await _plugin
                  .resolvePlatformSpecificImplementation<
                    MacOSFlutterLocalNotificationsPlugin
                  >()
                  ?.requestPermissions(
                    alert: true,
                    sound: true,
                    badge: false,
                  ) ??
              false;
        case TargetPlatform.windows:
        case TargetPlatform.linux:
        case TargetPlatform.fuchsia:
          return true;
      }
    } on Object {
      return false;
    }
  }

  @override
  Future<void> schedule({
    required TaskReminder reminder,
    required Task task,
  }) async {
    await _ensureInitialized();
    final scheduled = reminder.remindAt.toUtc();
    final id = _notificationId(reminder.id);
    if (!scheduled.isAfter(DateTime.now().toUtc()) || task.isCancelled) {
      await _plugin.cancel(id: id);
      return;
    }

    await _plugin.cancel(id: id);
    final mode = await _androidMode();
    await _plugin.zonedSchedule(
      id: id,
      title: task.title,
      body: 'Напоминание о задаче',
      scheduledDate: tz.TZDateTime.from(scheduled, tz.local),
      notificationDetails: NotificationDetails(
        android: const AndroidNotificationDetails(
          'zadachnik_reminders',
          'Напоминания',
          channelDescription: 'Напоминания о задачах Ежедневника',
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        macOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
        ),
        windows: const WindowsNotificationDetails(),
      ),
      androidScheduleMode: mode,
      payload: task.id,
    );
  }

  Future<AndroidScheduleMode> _androidMode() async {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return AndroidScheduleMode.exactAllowWhileIdle;
    }
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final canExact = await android?.canScheduleExactNotifications() ?? false;
    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  @override
  Future<void> cancel(String reminderId) async {
    await _ensureInitialized();
    await _plugin.cancel(id: _notificationId(reminderId));
  }

  @override
  Future<void> cancelAll() async {
    await _ensureInitialized();
    await _plugin.cancelAll();
  }

  static int _notificationId(String id) {
    var hash = 0x811c9dc5;
    for (final unit in id.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
