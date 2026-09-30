import 'dart:convert';

import 'package:clientpro/data/prefs.dart';
import 'package:clientpro/data/sample_data.dart';
import 'package:clientpro/data/store.dart';
import 'package:clientpro/models/models.dart';
import 'package:clientpro/services/contact_actions.dart';
import 'package:clientpro/services/exporter.dart';
import 'package:clientpro/services/format.dart';
import 'package:clientpro/services/invoice_pdf.dart';
import 'package:clientpro/services/notifications.dart';
import 'package:excel/excel.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('ar'));

  group('Formatting', () {
    test('parses Arabic and Latin digits', () {
      expect(Fmt.parse('١٢٣٫٥'), 123.5);
      expect(Fmt.parse('1,5'), 1.5);
      expect(Fmt.parse('abc'), 0);
    });

    test('money with symbol and digit style', () {
      Fmt.currency = 'EGP';
      Fmt.arabicDigits = false;
      expect(Fmt.money(1234.5), '1,234.5 ج.م');
      Fmt.arabicDigits = true;
      expect(Fmt.money(1200), '١,٢٠٠ ج.م');
      Fmt.arabicDigits = false;
    });
  });

  test('WhatsApp numbers are converted to international format', () {
    expect(ContactActions.international('010 1234 5678', '20'), '201012345678');
    expect(ContactActions.international('+966 50 123 4567', '20'), '966501234567');
    expect(ContactActions.international('00971501234567', '20'), '971501234567');
    expect(ContactActions.international('٠١٠١٢٣٤٥٦٧٨', '20'), '201012345678');
    expect(
      ContactActions.whatsapp('01012345678', '20', text: 'مرحبا').toString(),
      startsWith('https://wa.me/201012345678?text='),
    );
  });

  group('Notification plan', () {
    late DevicePrefs prefs;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await DevicePrefs.load();
    });

    test('includes tasks, repeating tasks, invoices, birthdays, daily and monthly reminders', () {
      final now = DateTime(2026, 9, 25, 12);
      final store = AppStore(persist: false);
      final c = Customer(name: 'سارة', birthday: DateTime(1995, 10, 2));
      store.upsert(store.customers, c);
      store.upsert(store.tasks, TaskItem(title: 'مكالمة', dueDate: DateTime(2026, 9, 26, 10), customerId: c.id));
      store.upsert(
        store.tasks,
        TaskItem(title: 'متابعة شهرية', dueDate: DateTime(2026, 8, 5, 9), repeat: RepeatRule.monthly),
      );
      store.upsert(store.tasks, TaskItem(title: 'قديمة', dueDate: DateTime(2026, 9, 1)));
      store.upsert(store.tasks, TaskItem(title: 'بدون تذكير', dueDate: DateTime(2026, 9, 27), reminder: false));
      store.upsert(
        store.invoices,
        Invoice(
          customerId: c.id,
          items: [InvoiceItem(name: 'x', unitPrice: 100)],
          dueDate: DateTime(2026, 9, 30),
        ),
      );

      final plan = NotificationService.buildPlan(store, prefs, now);
      final titles = plan.map((p) => p.title).toList();

      expect(titles, contains('ملخص يومك'));
      expect(titles, contains('تقرير الشهر جاهز للتصدير'));
      expect(titles, contains('⏰ مكالمة'));
      expect(titles.where((t) => t.contains('قديمة')), isEmpty);
      expect(titles.where((t) => t.contains('بدون تذكير')), isEmpty);
      expect(titles, contains('فاتورة تستحق غداً'));
      expect(titles, contains('فاتورة مستحقة اليوم'));
      expect(titles, contains('🎂 عيد ميلاد سارة'));

      final monthly = plan.firstWhere((p) => p.title == '⏰ متابعة شهرية');
      expect(monthly.repeat, DateTimeComponents.dayOfMonthAndTime);
      expect(monthly.at, DateTime(2026, 10, 5, 9));
      expect(plan.every((p) => p.at.isAfter(now)), isTrue);
    });

    test('follow-up digest lists unpaid bills, salaries and who owes whom; debts get due reminders', () {
      prefs
        ..dailyAgenda = false
        ..monthlyExportReminder = false
        ..notifyBills = false
        ..followUpEveryDays = 3
        ..followUpTime = 19 * 60;
      final now = DateTime(2026, 9, 3, 12);
      final store = AppStore(persist: false);
      store.upsert(store.fixedExpenses, FixedExpense(title: 'الإيجار', amount: 4000, dueDay: 1));
      store.upsert(store.employees, Employee(name: 'كريم', salary: 5000, payDay: 5));
      store.upsert(
        store.debts,
        Debt(person: 'محمد', amount: 2000, direction: DebtDirection.owedToMe, dueDate: DateTime(2026, 9, 10)),
      );
      store.upsert(store.debts, Debt(person: 'المطبعة', amount: 700, direction: DebtDirection.iOwe));

      final plan = NotificationService.buildPlan(store, prefs, now);
      final digests = plan.where((p) => p.title.startsWith('📋')).toList();
      expect(digests.first.at, DateTime(2026, 9, 3, 19));
      expect(digests[1].at, DateTime(2026, 9, 6, 19));
      expect(digests.first.body, contains('الإيجار'));
      expect(digests.first.body, isNot(contains('كريم')), reason: 'pay day (5th) not reached yet');
      expect(digests[1].body, contains('كريم'));
      expect(digests.first.body, contains('محمد'));
      expect(digests.first.body, contains('المطبعة'));

      final debtReminders = plan.where((p) => p.title.contains('محمد')).toList();
      expect(debtReminders.map((p) => p.at), [
        DateTime(2026, 9, 10, 11),
        DateTime(2026, 9, 17, 11),
        DateTime(2026, 9, 24, 11),
        DateTime(2026, 10, 1, 11),
      ]);

      // Once everything is paid, the digest has nothing to say.
      store.payFixed(store.fixedExpenses.all.first, now);
      store.paySalary(store.employees.all.first, now);
      for (final d in store.debts.all) {
        store.addDebtPayment(d, d.amount);
      }
      final after = NotificationService.buildPlan(store, prefs, now);
      expect(after.where((p) => p.title.startsWith('📋') || p.title.contains('محمد')), isEmpty);
    });

    test('respects switches', () {
      prefs
        ..dailyAgenda = false
        ..monthlyExportReminder = false
        ..notifyTasks = false;
      final store = AppStore(persist: false);
      store.upsert(store.tasks, TaskItem(title: 'x', dueDate: DateTime.now().add(const Duration(days: 1))));
      expect(NotificationService.buildPlan(store, prefs, DateTime.now()), isEmpty);
    });
  });

  test('monthly Excel export has all sheets and correct totals', () {
    final store = AppStore(persist: false);
    loadSampleData(store);
    final now = DateTime.now();
    final bytes = Exporter(store).buildMonthlyWorkbook(now);
    final excel = Excel.decodeBytes(bytes);
    expect(
      excel.tables.keys,
      containsAll(['الملخص', 'الفواتير', 'المدفوعات', 'المصروفات', 'ربحية العملاء', 'العملاء', 'المهام']),
    );
    expect(excel.tables['العملاء']!.maxRows, store.customers.items.length + 1);

    final start = DateTime(now.year, now.month);
    final end = DateTime(now.year, now.month + 1);
    final expected = store.allPayments
        .where((p) => !p.$1.date.isBefore(start) && p.$1.date.isBefore(end))
        .fold<double>(0, (s, p) => s + p.$1.amount);
    final revenueRow = excel.tables['الملخص']!.rows.firstWhere((r) => r.first?.value.toString() == 'المحصّل (مدفوعات)');
    final cell = revenueRow[1]!.value;
    final value = cell is DoubleCellValue ? cell.value : (cell as IntCellValue).value.toDouble();
    expect(value, closeTo(expected, 0.001));
  });

  test('restore rejects foreign files and accepts backups', () {
    final store = AppStore(persist: false);
    final exporter = Exporter(store);
    expect(exporter.restoreFromJson('{"x":1}', merge: true), isNotNull);
    expect(exporter.restoreFromJson('not json', merge: true), isNotNull);

    final source = AppStore(persist: false);
    loadSampleData(source);
    final json = jsonEncode({'app': 'ClientPro', 'customers': source.customers.toJson()});
    expect(exporter.restoreFromJson(json, merge: false), isNull);
    expect(store.customers.items.length, source.customers.items.length);
  });

  test('invoice PDF renders with Arabic font', () async {
    final store = AppStore(persist: false);
    loadSampleData(store);
    final bytes = await InvoicePdf.build(store, store.invoices.all.first);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(5000));
  });
}
