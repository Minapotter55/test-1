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

  /// Long bodies (the follow-up summary) expand to show every line on Android.
  static NotificationDetails _detailsFor(String body) {
    if (!body.contains('\n') && body.length < 60) return _details;
    return NotificationDetails(
      android: AndroidNotificationDetails(
        'clientpro_reminders',
        'التذكيرات',
        channelDescription: 'تذكيرات المهام والفواتير والعملاء',
        importance: Importance.high,
        priority: Priority.high,
        styleInformation: BigTextStyleInformation(body),
      ),
      iOS: const DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
    );
  }

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
          notificationDetails: _detailsFor(p.body),
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

    if (prefs.notifyInvoices) {
      for (final c in store.customers.all) {
        final end = c.contractEnd;
        if (end == null || c.status == CustomerStatus.inactive) continue;
        for (final daysBefore in const [14, 3, 0]) {
          final at = DateTime(end.year, end.month, end.day - daysBefore, 10);
          if (!at.isAfter(now)) continue;
          oneOff.add(
            PlannedNotification(
              at: at,
              title: daysBefore == 0
                  ? '📄 عقد ${c.name} بينتهي النهارده'
                  : '📄 عقد ${c.name} بينتهي بعد $daysBefore يوم',
              body: 'كلّمه عشان التجديد${c.fee > 0 ? ' — ${c.feeCycle.label} ${Fmt.money(c.fee)}' : ''}',
            ),
          );
        }
      }
    }

    if (prefs.notifyBills) {
      // Fixed bills and salaries for this month and the next one, so the
      // reminders keep coming even if the app isn't opened for a while.
      for (final offset in const [0, 1]) {
        final month = DateTime(now.year, now.month + offset);
        final key = Fmt.monthKey(month);
        for (final f in store.fixedExpenses.all) {
          if (!f.isActive || store.fixedPayment(f.id, key) != null) continue;
          final amount = f.variable ? 'شوف الفاتورة وسجّلها' : Fmt.money(f.amount);
          final due = DateTime(month.year, month.month, f.dueDay, 10);
          final dayBefore = due.subtract(const Duration(days: 1));
          if (dayBefore.isAfter(now)) {
            oneOff.add(PlannedNotification(at: dayBefore, title: '🧾 ${f.title} بكرة', body: amount));
          }
          if (due.isAfter(now)) {
            oneOff.add(PlannedNotification(at: due, title: '🧾 ميعاد دفع ${f.title} النهارده', body: amount));
          }
        }
        final byDay = <int, List<Payslip>>{};
        for (final slip in store.payroll(month)) {
          if (slip.isPaid || !slip.employee.isActive) continue;
          byDay.putIfAbsent(slip.employee.payDay, () => []).add(slip);
        }
        byDay.forEach((day, slips) {
          final at = DateTime(month.year, month.month, day, 10);
          if (!at.isAfter(now)) return;
          final total = slips.fold(0.0, (s, p) => s + p.net);
          oneOff.add(
            PlannedNotification(
              at: at,
              title: '💰 ميعاد المرتبات النهارده',
              body: slips.length == 1
                  ? '${slips.first.employee.name} — ${Fmt.money(total)}'
                  : '${slips.length} موظفين — ${Fmt.money(total)}',
            ),
          );
        });
      }
    }

    if (prefs.followUpDigest) {
      // The next few follow-ups, each worked out for its own date, so it
      // stays right as bills and pay days come due. Rebuilt on every change.
      final every = prefs.followUpEveryDays;
      final minutes = prefs.followUpTime;
      var at = DateTime(now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
      if (!at.isAfter(now)) at = at.add(Duration(days: every));
      for (var i = 0; i < 6; i++) {
        final f = store.followUp(at);
        if (!f.isEmpty) {
          oneOff.add(PlannedNotification(at: at, title: '📋 متابعة: مين اخد ومين عليه فلوس', body: f.summary()));
        }
        at = DateTime(at.year, at.month, at.day + every, at.hour, at.minute);
      }
    }

    if (prefs.notifyDebts) {
      for (final d in store.debts.all) {
        final due = d.dueDate;
        if (due == null || d.isSettled) continue;
        final mine = d.direction == DebtDirection.owedToMe;
        // On the due date, then weekly for three weeks while still open.
        for (final week in const [0, 1, 2, 3]) {
          final at = DateTime(due.year, due.month, due.day + week * 7, 11);
          if (!at.isAfter(now)) continue;
          oneOff.add(
            PlannedNotification(
              at: at,
              title: mine
                  ? (week == 0 ? '💵 النهارده ميعاد تحصيل من ${d.person}' : '💵 ${d.person} لسه عليه فلوس')
                  : (week == 0 ? '💸 النهارده ميعاد سداد لـ ${d.person}' : '💸 لسه عليك فلوس لـ ${d.person}'),
              body:
                  '${mine ? 'باقي ليك' : 'باقي عليك'} ${Fmt.money(d.remaining)}${d.reason.isEmpty ? '' : ' — ${d.reason}'}',
            ),
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
