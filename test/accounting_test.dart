import 'package:clientpro/data/store.dart';
import 'package:clientpro/models/models.dart';
import 'package:clientpro/services/format.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  setUpAll(() => initializeDateFormatting('ar'));

  test('client profit = money received - money spent on the client', () {
    final s = AppStore(persist: false);
    final c = Customer(name: 'عميل', fee: 5000, feeCycle: FeeCycle.monthly);
    s.upsert(s.customers, c);
    s.receiveMoney(c, 5000);
    s.upsert(s.expenses, Expense(title: 'إعلانات', amount: 1200, customerId: c.id));
    s.upsert(s.expenses, Expense(title: 'إيجار', amount: 3000)); // general, not on this client

    final a = s.accountOf(c);
    expect(a.income, 5000);
    expect(a.spent, 1200);
    expect(a.profit, 3800);
    expect(a.margin, closeTo(76, 0.01));
    expect(a.balance, 0);
  });

  test('period filter only counts money inside the range', () {
    final s = AppStore(persist: false);
    final c = Customer(name: 'عميل');
    s.upsert(s.customers, c);
    s.receiveMoney(c, 1000, date: DateTime(2026, 8, 10));
    s.receiveMoney(c, 2000, date: DateTime(2026, 9, 10));
    s.upsert(s.expenses, Expense(title: 'x', amount: 300, date: DateTime(2026, 9, 11), customerId: c.id));
    final sept = s.accountOf(c, from: DateTime(2026, 9), to: DateTime(2026, 10));
    expect(sept.income, 2000);
    expect(sept.spent, 300);
  });

  test('monthly invoices are issued once per subscriber and track who has not paid', () {
    final s = AppStore(persist: false);
    final a = Customer(
      name: 'مشترك',
      fee: 3000,
      feeCycle: FeeCycle.monthly,
      status: CustomerStatus.active,
      billingDay: 10,
    );
    final b = Customer(name: 'مشترك موقوف', fee: 3000, feeCycle: FeeCycle.monthly, status: CustomerStatus.inactive);
    final c = Customer(name: 'بدون اشتراك');
    for (final x in [a, b, c]) {
      s.upsert(s.customers, x);
    }
    final month = DateTime(2026, 9);
    expect(s.subscribersToBill(month).map((x) => x.name), ['مشترك']);
    expect(s.issueMonthlyInvoices(month), 1);
    expect(s.issueMonthlyInvoices(month), 0, reason: 'must not issue twice');

    final inv = s.subscriptionInvoice(a.id, Fmt.monthKey(month))!;
    expect(inv.total, 3000);
    expect(inv.dueDate, DateTime(2026, 9, 10));
    expect(s.unpaidSubscriptions(month).length, 1);

    inv.payments.add(Payment(amount: 3000));
    s.upsert(s.invoices, inv);
    expect(s.unpaidSubscriptions(month), isEmpty);
  });

  test('new fields survive sync JSON', () {
    final s = AppStore(persist: false);
    final c = Customer(name: 'x', fee: 2500, feeCycle: FeeCycle.monthly, billingDay: 7);
    s.upsert(s.customers, c);
    s.upsert(s.expenses, Expense(title: 'e', amount: 10, customerId: c.id));
    s.issueMonthlyInvoices(DateTime(2026, 9));
    final copy = AppStore(persist: false)..replaceWith(s.snapshot());
    final c2 = copy.customers.items[c.id]!;
    expect((c2.fee, c2.feeCycle, c2.billingDay), (2500.0, FeeCycle.monthly, 7));
    expect(copy.expenses.all.single.customerId, c.id);
    expect(copy.invoices.all.single.periodKey, '2026-09');
  });

  test('deleting a client keeps its expenses as general expenses', () {
    final s = AppStore(persist: false);
    final c = Customer(name: 'x');
    s.upsert(s.customers, c);
    s.upsert(s.expenses, Expense(title: 'e', amount: 10, customerId: c.id));
    s.deleteCustomer(c);
    expect(s.expenses.all.single.customerId, isNull);
  });

  test('custom lists, contract fields and custom expense category sync', () {
    final s = AppStore(persist: false);
    s.updateBusiness((b) {
      b.sectors.add('مركز علاج طبيعي');
      b.clientFieldTemplates.add('اسم المدير المالي');
      b.expenseCategories.add('طباعة');
    });
    final c = Customer(
      name: 'معمل الخبراء',
      sector: 'معمل تحاليل',
      contactPerson: 'د. أحمد',
      contractEnd: DateTime.now().add(const Duration(days: 10)),
      services: ['حملة إعلانية'],
    );
    s.upsert(s.customers, c);
    s.upsert(s.expenses, Expense(title: 'بروشورات', amount: 500, customerId: c.id, customCategory: 'طباعة'));

    final copy = AppStore(persist: false)..replaceWith(s.snapshot());
    expect(copy.business.sectors, contains('مركز علاج طبيعي'));
    expect(copy.business.clientFieldTemplates, contains('اسم المدير المالي'));
    final c2 = copy.customers.items[c.id]!;
    expect((c2.sector, c2.contactPerson), ('معمل تحاليل', 'د. أحمد'));
    expect(c2.services, ['حملة إعلانية']);
    expect(c2.contractEndingSoon, isTrue);
    expect(copy.expenses.all.single.categoryLabel, 'طباعة');
  });
}
