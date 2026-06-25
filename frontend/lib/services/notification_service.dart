import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter/foundation.dart';
import 'package:timezone/timezone.dart' as tz;
import 'package:timezone/data/latest_all.dart' as tzData;

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      // Initialize timezone data
      tzData.initializeTimeZones();
      
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );
      const settings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _plugin.initialize(settings);
      _initialized = true;
      debugPrint('Notification service initialized');
    } catch (e) {
      debugPrint('Notification initialization error: $e');
      _initialized = false;
    }
  }

  Future<void> showTaskReminder(String title, String body) async {
    if (!_initialized) {
      debugPrint('Notification service not initialized, skipping notification');
      return;
    }

    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'homework_tracker',
          'Homework Reminders',
          channelDescription: 'Notifications for upcoming homework deadlines',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        title.hashCode,
        title,
        body,
        details,
      );
      debugPrint('Notification shown: $title');
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  Future<void> showDueSoonNotification(String taskTitle, String dueDate) async {
    await showTaskReminder(
      '⏰ Due Soon!',
      '"$taskTitle" is due $dueDate',
    );
  }

  Future<void> showOverdueNotification(String taskTitle, String dueDate) async {
    if (!_initialized) {
      debugPrint('Notification service not initialized, skipping notification');
      return;
    }

    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'homework_tracker_overdue',
          'Overdue Tasks',
          channelDescription: 'Notifications for overdue homework tasks',
          importance: Importance.max,
          priority: Priority.max,
          color: null,
          enableLights: true,
          enableVibration: true,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      await _plugin.show(
        'overdue_${taskTitle.hashCode}'.hashCode,
        '🚨 OVERDUE!',
        '"$taskTitle" was due $dueDate',
        details,
      );
      debugPrint('Overdue notification shown: $taskTitle');
    } catch (e) {
      debugPrint('Notification error: $e');
    }
  }

  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
  }) async {
    if (!_initialized) {
      debugPrint('Notification service not initialized, skipping scheduled notification');
      return;
    }

    try {
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'homework_tracker_scheduled',
          'Scheduled Reminders',
          channelDescription: 'Scheduled notifications for homework deadlines',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      );

      // Convert DateTime to TZDateTime
      final tzScheduledDate = tz.TZDateTime.from(scheduledDate, tz.local);

      await _plugin.zonedSchedule(
        id,
        title,
        body,
        tzScheduledDate,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      );
      debugPrint('Scheduled notification: $title for $scheduledDate');
    } catch (e) {
      debugPrint('Schedule notification error: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
      debugPrint('All notifications cancelled');
    } catch (e) {
      debugPrint('Cancel notifications error: $e');
    }
  }
}
