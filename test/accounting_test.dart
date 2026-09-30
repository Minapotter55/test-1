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

  group('payroll', () {
    final month = DateTime(2026, 9);
    const key = '2026-09';

    test('net salary = base + bonus - deduction - advance, paid once', () {
      final s = AppStore(persist: false);
      final e = Employee(name: 'أحمد', salary: 6000);
      s.upsert(s.employees, e);
      s.saveAdjustment(SalaryAdjustment(employeeId: e.id, type: AdjustmentType.bonus, amount: 500, periodKey: key));
      s.saveAdjustment(SalaryAdjustment(employeeId: e.id, type: AdjustmentType.deduction, amount: 200, periodKey: key));
      s.saveAdjustment(SalaryAdjustment(employeeId: e.id, type: AdjustmentType.absence, amount: 200, periodKey: key));
      final adv = SalaryAdjustment(
        employeeId: e.id,
        type: AdjustmentType.advance,
        amount: 1000,
        periodKey: key,
        date: DateTime(2026, 9, 5),
      );
      s.saveAdjustment(adv);

      // The advance is cash that already left: it's an expense now.
      expect(s.expenses.all.single.amount, 1000);
      expect(s.expenses.all.single.category, ExpenseCategory.salaries);

      final slip = s.payslip(e, month);
      expect((slip.additions, slip.deductions, slip.advances), (500.0, 400.0, 1000.0));
      expect(slip.gross, 6100);
      expect(slip.net, 5100);
      expect(slip.isPaid, isFalse);

      expect(s.payAllSalaries(month), 1);
      expect(s.payAllSalaries(month), 0, reason: 'must not pay twice');
      expect(s.payslip(e, month).isPaid, isTrue);
      // Total cost of the employee this month = advance + net = gross.
      expect(s.expenses.all.fold<double>(0, (t, x) => t + x.amount), 6100);

      // Other months are untouched.
      expect(s.payslip(e, DateTime(2026, 10)).net, 6000);
    });

    test('changing an advance to a deduction removes its expense', () {
      final s = AppStore(persist: false);
      final e = Employee(name: 'x', salary: 3000);
      s.upsert(s.employees, e);
      final a = SalaryAdjustment(employeeId: e.id, type: AdjustmentType.advance, amount: 500, periodKey: key);
      s.saveAdjustment(a);
      expect(s.expenses.items.length, 1);
      a.type = AdjustmentType.deduction;
      s.saveAdjustment(a);
      expect(s.expenses.items, isEmpty);
      a.type = AdjustmentType.advance;
      s.saveAdjustment(a);
      s.deleteAdjustment(a);
      expect(s.expenses.items, isEmpty);
      expect(s.adjustments.items, isEmpty);
    });

    test('inactive employees are skipped; deleting keeps paid salaries', () {
      final s = AppStore(persist: false);
      final a = Employee(name: 'a', salary: 1000);
      final b = Employee(name: 'b', salary: 2000, isActive: false);
      s.upsert(s.employees, a);
      s.upsert(s.employees, b);
      expect(s.payroll(month).map((p) => p.employee.name), ['a']);
      expect(s.monthlySalaries, 1000);
      s.paySalary(a, month);
      s.deleteEmployee(a);
      expect(s.expenses.all.single.amount, 1000);
    });
  });

  test('fixed expenses: pay once per month, variable ones ask for the amount', () {
    final s = AppStore(persist: false);
    final rent = FixedExpense(title: 'إيجار', amount: 4000, category: ExpenseCategory.rent, dueDay: 1);
    final power = FixedExpense(title: 'كهرباء', amount: 400, category: ExpenseCategory.utilities, variable: true);
    final off = FixedExpense(title: 'قديم', amount: 99, isActive: false);
    for (final f in [rent, power, off]) {
      s.upsert(s.fixedExpenses, f);
    }
    final month = DateTime(2026, 9);
    expect(s.monthlyFixedTotal, 4400);
    expect(s.unpaidFixed(month).length, 2);
    expect(s.payAllFixed(month), 1, reason: 'variable bills are recorded by hand');
    expect(s.payAllFixed(month), 0);
    s.payFixed(power, month, amount: 523);
    expect(s.unpaidFixed(month), isEmpty);
    expect(s.unpaidFixed(DateTime(2026, 10)).length, 2);
    final paid = s.fixedPayment(power.id, '2026-09')!;
    expect((paid.amount, paid.category), (523.0, ExpenseCategory.utilities));

    // Paying again for the same month updates instead of duplicating.
    s.payFixed(power, month, amount: 530);
    expect(s.expenses.items.length, 2);
  });

  test('employees, adjustments and fixed expenses survive sync JSON', () {
    final s = AppStore(persist: false);
    final e = Employee(
      name: 'سارة',
      jobTitle: 'مصممة',
      salary: 7000,
      payDay: 25,
      customFields: [CustomField(key: 'بنك', value: 'CIB')],
    );
    s.upsert(s.employees, e);
    s.saveAdjustment(
      SalaryAdjustment(
        employeeId: e.id,
        type: AdjustmentType.bonus,
        amount: 300,
        periodKey: '2026-09',
        reason: 'تارجت',
      ),
    );
    final f = FixedExpense(title: 'نت', amount: 500, category: ExpenseCategory.utilities, dueDay: 5, variable: true);
    s.upsert(s.fixedExpenses, f);
    s.payFixed(f, DateTime(2026, 9));
    s.paySalary(e, DateTime(2026, 9));

    final copy = AppStore(persist: false)..replaceWith(s.snapshot());
    final e2 = copy.employees.items[e.id]!;
    expect((e2.name, e2.jobTitle, e2.salary, e2.payDay), ('سارة', 'مصممة', 7000.0, 25));
    expect(e2.customFields.single.value, 'CIB');
    final a2 = copy.adjustments.all.single;
    expect((a2.type, a2.amount, a2.reason), (AdjustmentType.bonus, 300.0, 'تارجت'));
    final f2 = copy.fixedExpenses.items[f.id]!;
    expect((f2.dueDay, f2.variable), (5, true));
    expect(copy.fixedPayment(f.id, '2026-09'), isNotNull);
    expect(copy.payslip(e2, DateTime(2026, 9)).isPaid, isTrue);
  });
}
