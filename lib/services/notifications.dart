import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/prefs.dart';
import '../data/store.dart';
import '../models/models.dart';
import 'format.dart';

/// Local notifications: task reminders (incl. repeating), invoice due dates,
/// customer birthdays, a daily agenda and a monthly export reminder.
///
/// Everything is rebuilt from the data whenever it changes, so reminders
/// stay correct after edits and after data arrives from another device.
class NotificationService {
  NotificationService._();
  static final instance = NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// iOS keeps at most 64 pending notifications per app.
  static const _maxPending = 60;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'clientpro_reminders',
      'التذكيرات',
      channelDescription: 'تذكيرات المهام والفواتير والعملاء',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
  );

  Future<void> init() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      tzdata.initializeTimeZones();
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } catch (e) {
      debugPrint('Timezone init failed, using UTC: $e');
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<bool> requestPermission() async {
    if (!_ready) return false;
    if (Platform.isAndroid) {
      final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, badge: true, sound: true) ?? false;
  }

  Future<void> showNow(String title, String body) async {
    if (!_ready) return;
    await _plugin.show(id: 999999, title: title, body: body, notificationDetails: _details);
  }

  /// Rebuilds every scheduled notification from the current data.
  Future<void> rescheduleAll(AppStore store, DevicePrefs prefs) async {
    if (!_ready) return;
    await _plugin.cancelAllPendingNotifications();
    final plans = buildPlan(store, prefs, DateTime.now());
    var id = 1;
    for (final p in plans.take(_maxPending)) {
      try {
        await _plugin.zonedSchedule(
          id: id++,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.at, tz.local),
          notificationDetails: _details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          matchDateTimeComponents: p.repeat,
        );
      } catch (e) {
        debugPrint('Failed to schedule "${p.title}": $e');
      }
    }
  }

  /// Pure planning logic (unit-tested): what to notify, when.
  static List<PlannedNotification> buildPlan(AppStore store, DevicePrefs prefs, DateTime now) {
    final repeating = <PlannedNotification>[];
    final oneOff = <PlannedNotification>[];

    if (prefs.dailyAgenda) {
      final minutes = prefs.dailyAgendaTime;
      var at = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
      if (!at.isAfter(now)) at = at.add(const Duration(days: 1));
      repeating.add(
        PlannedNotification(
          at: at,
          title: 'ملخص يومك',
          body: 'راجع مهامك ومواعيد المتابعة والفواتير المستحقة اليوم',
          repeat: DateTimeComponents.time,
        ),
      );
    }

    if (prefs.monthlyExportReminder) {
      var at = DateTime(now.year, now.month, 1, 10);
      if (!at.isAfter(now)) at = DateTime(now.year, now.month + 1, 1, 10);
      repeating.add(
        PlannedNotification(
          at: at,
          title: 'تقرير الشهر جاهز للتصدير',
          body: 'افتح التطبيق لتصدير بيانات الشهر الماضي إلى Excel ورفعها على Google Drive',
          repeat: DateTimeComponents.dayOfMonthAndTime,
        ),
      );
    }

    if (prefs.notifyTasks) {
      for (final t in store.tasks.all) {
        final due = t.dueDate;
        if (t.isDone || !t.reminder || due == null) continue;
        final customer = store.customer(t.customerId);
        final body = customer == null ? (t.notes.isEmpty ? 'موعد المهمة الآن' : t.notes) : 'مع ${customer.name}';
        final repeatComponents = switch (t.repeat) {
          RepeatRule.none => null,
          RepeatRule.daily => DateTimeComponents.time,
          RepeatRule.weekly => DateTimeComponents.dayOfWeekAndTime,
          RepeatRule.monthly => DateTimeComponents.dayOfMonthAndTime,
          RepeatRule.yearly => DateTimeComponents.dateAndTime,
        };
        var at = due;
        if (repeatComponents != null) {
          while (!at.isAfter(now)) {
            at = nextOccurrence(at, t.repeat);
          }
          repeating.add(PlannedNotification(at: at, title: '⏰ ${t.title}', body: body, repeat: repeatComponents));
        } else if (at.isAfter(now)) {
          oneOff.add(PlannedNotification(at: at, title: '⏰ ${t.title}', body: body));
        }
      }
    }

    if (prefs.notifyInvoices) {
      for (final inv in store.invoices.all) {
        if (!inv.status.isOutstanding) continue;
        final name = store.customer(inv.customerId)?.name ?? 'عميل';
        final due = DateTime(inv.dueDate.year, inv.dueDate.month, inv.dueDate.day, 10);
        final dayBefore = due.subtract(const Duration(days: 1));
        if (dayBefore.isAfter(now)) {
          oneOff.add(
            PlannedNotification(
              at: dayBefore,
              title: 'فاتورة تستحق غداً',
              body: '${inv.number} — $name — المتبقي ${Fmt.money(inv.balance)}',
            ),
          );
        }
        if (due.isAfter(now)) {
          oneOff.add(
            PlannedNotification(
              at: due,
              title: 'فاتورة مستحقة اليوم',
              body: '${inv.number} — $name — المتبقي ${Fmt.money(inv.balance)}',
            ),
          );
        }
        final week = due.add(const Duration(days: 7));
        if (week.isAfter(now)) {
          oneOff.add(
            PlannedNotification(at: week, title: 'فاتورة متأخرة أسبوعاً', body: 'تابع التحصيل: ${inv.number} — $name'),
          );
        }
      }
    }

    if (prefs.notifyBirthdays) {
      for (final c in store.customers.all) {
        final b = c.birthday;
        if (b == null) continue;
        var at = DateTime(now.year, b.month, b.day, 9);
        if (!at.isAfter(now)) at = DateTime(now.year + 1, b.month, b.day, 9);
        oneOff.add(
          PlannedNotification(at: at, title: '🎂 عيد ميلاد ${c.name}', body: 'فرصة رائعة لرسالة تهنئة أو عرض خاص'),
        );
      }
    }

    oneOff.sort((a, b) => a.at.compareTo(b.at));
    return [...repeating, ...oneOff];
  }
}

class PlannedNotification {
  PlannedNotification({required this.at, required this.title, required this.body, this.repeat});
  final DateTime at;
  final String title;
  final String body;
  final DateTimeComponents? repeat;
}
