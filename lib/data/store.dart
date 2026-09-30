import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';
import '../services/format.dart';

/// A typed set of records keyed by id.
class Collection<T extends Entity> {
  Collection(this.key, this.fromJson);

  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, T> items = {};

  List<T> get all => items.values.toList();

  List<Map<String, dynamic>> toJson() => items.values.map((e) => e.toJson()).toList();

  void load(Object? json) {
    items.clear();
    if (json is! List) return;
    for (final m in json.whereType<Map>()) {
      final e = fromJson(Map<String, dynamic>.from(m));
      items[e.id] = e;
    }
  }

  /// Last-writer-wins per record; tombstones beat older edits.
  bool merge(Object? json, Map<String, int> tombstones) {
    var changed = false;
    if (json is List) {
      for (final m in json.whereType<Map>()) {
        final remote = fromJson(Map<String, dynamic>.from(m));
        final deletedAt = tombstones[remote.id];
        if (deletedAt != null && deletedAt >= remote.updatedAt) continue;
        final local = items[remote.id];
        if (local == null || remote.updatedAt > local.updatedAt) {
          items[remote.id] = remote;
          changed = true;
        }
      }
    }
    tombstones.forEach((id, deletedAt) {
      final local = items[id];
      if (local != null && deletedAt >= local.updatedAt) {
        items.remove(id);
        changed = true;
      }
    });
    return changed;
  }
}

/// All app data, kept in memory and persisted as one JSON file.
/// The same JSON is what gets synced to Google Drive and backed up.
class AppStore extends ChangeNotifier {
  AppStore({this.persist = true});

  /// Tests run without a file system.
  final bool persist;

  static const schemaVersion = 1;
  static const fileName = 'clientpro_data.json';

  final customers = Collection<Customer>('customers', Customer.fromJson);
  final deals = Collection<Deal>('deals', Deal.fromJson);
  final invoices = Collection<Invoice>('invoices', Invoice.fromJson);
  final products = Collection<Product>('products', Product.fromJson);
  final tasks = Collection<TaskItem>('tasks', TaskItem.fromJson);
  final interactions = Collection<Interaction>('interactions', Interaction.fromJson);
  final expenses = Collection<Expense>('expenses', Expense.fromJson);
  final employees = Collection<Employee>('employees', Employee.fromJson);
  final adjustments = Collection<SalaryAdjustment>('adjustments', SalaryAdjustment.fromJson);
  final fixedExpenses = Collection<FixedExpense>('fixedExpenses', FixedExpense.fromJson);
  final debts = Collection<Debt>('debts', Debt.fromJson);

  late final List<Collection> _collections = [
    customers,
    deals,
    invoices,
    products,
    tasks,
    interactions,
    expenses,
    employees,
    adjustments,
    fixedExpenses,
    debts,
  ];

  BusinessSettings business = BusinessSettings();
  final Map<String, int> tombstones = {};

  /// Bumped on every local edit (not on merges); sync uses it to know when to push.
  int revision = 0;
  bool loaded = false;

  Timer? _saveTimer;
  File? _file;

  // MARK: Persistence

  Future<void> load() async {
    if (persist) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File('${dir.path}/$fileName');
      if (await _file!.exists()) {
        try {
          final json = jsonDecode(await _file!.readAsString());
          if (json is Map<String, dynamic>) _apply(json);
        } catch (e) {
          debugPrint('Failed to read data file: $e');
          // Keep a copy of the unreadable file instead of overwriting it.
          await _file!.copy('${_file!.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        }
      }
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> snapshot() => {
    'app': 'ClientPro',
    'version': schemaVersion,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'business': business.toJson(),
    'tombstones': tombstones,
    for (final c in _collections) c.key: c.toJson(),
  };

  void _apply(Map<String, dynamic> json) {
    business = json['business'] is Map
        ? BusinessSettings.fromJson(Map<String, dynamic>.from(json['business'] as Map))
        : BusinessSettings();
    tombstones
      ..clear()
      ..addAll(_tombstones(json['tombstones']));
    for (final c in _collections) {
      c.load(json[c.key]);
    }
  }

  static Map<String, int> _tombstones(Object? json) {
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
    };
  }

  static bool isValidSnapshot(Object? json) => json is Map && json['app'] == 'ClientPro';

  /// Replaces everything (restore from a backup file).
  void replaceWith(Map<String, dynamic> json) {
    _apply(json);
    revision++;
    _changed();
  }

  /// Merges data coming from another device. Returns true if anything changed locally.
  bool mergeFrom(Map<String, dynamic> json) {
    var changed = false;
    final remoteTombstones = _tombstones(json['tombstones']);
    remoteTombstones.forEach((id, t) {
      if ((tombstones[id] ?? 0) < t) tombstones[id] = t;
    });
    for (final c in _collections) {
      if (c.merge(json[c.key], tombstones)) changed = true;
    }
    if (json['business'] is Map) {
      final remote = BusinessSettings.fromJson(Map<String, dynamic>.from(json['business'] as Map));
      if (remote.updatedAt > business.updatedAt) {
        // Never go backwards on invoice numbering.
        remote.nextInvoiceNumber = remote.nextInvoiceNumber > business.nextInvoiceNumber
            ? remote.nextInvoiceNumber
            : business.nextInvoiceNumber;
        business = remote;
        changed = true;
      } else if (remote.nextInvoiceNumber > business.nextInvoiceNumber) {
        business.nextInvoiceNumber = remote.nextInvoiceNumber;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _scheduleSave();
    }
    return changed;
  }

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final file = _file;
    if (file == null) return;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot()), flush: true);
    await tmp.rename(file.path);
  }

  // MARK: Generic edits

  void upsert<T extends Entity>(Collection<T> c, T item) {
    item.touch();
    c.items[item.id] = item;
    tombstones.remove(item.id);
    revision++;
    _changed();
  }

  void delete<T extends Entity>(Collection<T> c, String id) {
    if (c.items.remove(id) == null) return;
    tombstones[id] = DateTime.now().millisecondsSinceEpoch;
    revision++;
    _changed();
  }

  void updateBusiness(void Function(BusinessSettings b) edit) {
    edit(business);
    business.updatedAt = DateTime.now().millisecondsSinceEpoch;
    revision++;
    _changed();
  }

  void wipe() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in _collections) {
      for (final id in c.items.keys) {
        tombstones[id] = now;
      }
      c.items.clear();
    }
    revision++;
    _changed();
  }

  // MARK: Domain helpers

  Customer? customer(String? id) => id == null ? null : customers.items[id];

  List<Invoice> invoicesOf(String customerId) =>
      invoices.all.where((i) => i.customerId == customerId).toList()
        ..sort((a, b) => b.issueDate.compareTo(a.issueDate));

  List<Deal> dealsOf(String customerId) => deals.all.where((d) => d.customerId == customerId).toList();

  List<TaskItem> tasksOf(String customerId) => tasks.all.where((t) => t.customerId == customerId).toList();

  List<Interaction> interactionsOf(String customerId) =>
      interactions.all.where((i) => i.customerId == customerId).toList()..sort((a, b) => b.date.compareTo(a.date));

  double totalPaidBy(String customerId) =>
      invoicesOf(customerId).where((i) => i.state == InvoiceState.issued).fold(0.0, (s, i) => s + i.paidAmount);

  double totalInvoicedTo(String customerId) =>
      invoicesOf(customerId).where((i) => i.state == InvoiceState.issued).fold(0.0, (s, i) => s + i.total);

  double balanceOf(String customerId) =>
      invoicesOf(customerId).where((i) => i.status.isOutstanding).fold(0.0, (s, i) => s + i.balance);

  /// Every payment with its invoice, newest first.
  List<(Payment, Invoice)> get allPayments {
    final list = <(Payment, Invoice)>[
      for (final inv in invoices.all)
        if (inv.state != InvoiceState.cancelled)
          for (final p in inv.payments) (p, inv),
    ];
    list.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    return list;
  }

  String peekInvoiceNumber() => '${business.invoicePrefix}${business.nextInvoiceNumber.toString().padLeft(4, '0')}';

  /// Returns the next number and advances the counter.
  String takeInvoiceNumber() {
    final number = peekInvoiceNumber();
    updateBusiness((b) => b.nextInvoiceNumber += 1);
    return number;
  }

  void logInteraction(Customer c, InteractionType type, String summary, {DateTime? date}) {
    final when = date ?? DateTime.now();
    upsert(interactions, Interaction(customerId: c.id, type: type, summary: summary, date: when));
    if (c.lastContactAt == null || c.lastContactAt!.isBefore(when)) {
      c.lastContactAt = when;
      upsert(customers, c);
    }
  }

  void deleteCustomer(Customer c) {
    for (final i in invoicesOf(c.id)) {
      delete(invoices, i.id);
    }
    for (final d in dealsOf(c.id)) {
      delete(deals, d.id);
    }
    for (final i in interactionsOf(c.id)) {
      delete(interactions, i.id);
    }
    for (final t in tasksOf(c.id)) {
      t.customerId = null;
      upsert(tasks, t);
    }
    // Keep the money that was spent, just no longer linked to the client.
    for (final e in expensesOf(c.id)) {
      e.customerId = null;
      upsert(expenses, e);
    }
    delete(customers, c.id);
  }

  // MARK: Client accounting

  List<Expense> expensesOf(String customerId) =>
      expenses.all.where((e) => e.customerId == customerId).toList()..sort((a, b) => b.date.compareTo(a.date));

  /// Income, spend and profit for one client, optionally within [from, to).
  ClientAccount accountOf(Customer c, {DateTime? from, DateTime? to}) {
    bool inRange(DateTime d) => (from == null || !d.isBefore(from)) && (to == null || d.isBefore(to));
    final invs = invoicesOf(c.id).where((i) => i.state == InvoiceState.issued).toList();
    return ClientAccount(
      customer: c,
      income: invs.expand((i) => i.payments).where((p) => inRange(p.date)).fold(0.0, (s, p) => s + p.amount),
      invoiced: invs.where((i) => inRange(i.issueDate)).fold(0.0, (s, i) => s + i.total),
      spent: expensesOf(c.id).where((e) => inRange(e.date)).fold(0.0, (s, e) => s + e.amount),
      balance: invs.where((i) => i.status.isOutstanding).fold(0.0, (s, i) => s + i.balance),
    );
  }

  /// Every client that has any money movement or a price, most profitable first.
  List<ClientAccount> clientAccounts({DateTime? from, DateTime? to}) {
    final list = customers.all
        .map((c) => accountOf(c, from: from, to: to))
        .where((a) => a.income != 0 || a.spent != 0 || a.balance != 0 || a.invoiced != 0 || a.customer.fee > 0)
        .toList();
    list.sort((a, b) => b.profit.compareTo(a.profit));
    return list;
  }

  Invoice? subscriptionInvoice(String customerId, String periodKey) {
    for (final i in invoices.all) {
      if (i.customerId == customerId && i.periodKey == periodKey && i.state != InvoiceState.cancelled) return i;
    }
    return null;
  }

  /// Monthly subscribers that don't have an invoice for [month] yet.
  List<Customer> subscribersToBill(DateTime month) {
    final key = Fmt.monthKey(month);
    return customers.all
        .where((c) => c.feeCycle == FeeCycle.monthly && c.fee > 0 && c.status != CustomerStatus.inactive)
        .where((c) => subscriptionInvoice(c.id, key) == null)
        .toList();
  }

  /// Monthly subscribers whose invoice for [month] isn't fully paid.
  List<(Customer, Invoice)> unpaidSubscriptions(DateTime month) {
    final key = Fmt.monthKey(month);
    return [
      for (final c in customers.all)
        if (c.feeCycle == FeeCycle.monthly)
          if (subscriptionInvoice(c.id, key) case final inv? when inv.status.isOutstanding) (c, inv),
    ];
  }

  /// Issues this month's subscription invoice for every subscriber that doesn't have one.
  int issueMonthlyInvoices(DateTime month) {
    final list = subscribersToBill(month);
    for (final c in list) {
      upsert(invoices, subscriptionInvoiceFor(c, month));
    }
    return list.length;
  }

  Invoice subscriptionInvoiceFor(Customer c, DateTime month) {
    final day = c.billingDay.clamp(1, 28);
    return Invoice(
      number: takeInvoiceNumber(),
      customerId: c.id,
      issueDate: DateTime(month.year, month.month, 1),
      dueDate: DateTime(month.year, month.month, day),
      taxRate: business.defaultTaxRate,
      periodKey: Fmt.monthKey(month),
      items: [InvoiceItem(name: 'اشتراك شهر ${Fmt.month(month)}', quantity: 1, unitPrice: c.fee)],
    );
  }

  /// "I received money from this client": creates a paid invoice in one step.
  Invoice receiveMoney(
    Customer c,
    double amount, {
    String note = '',
    PaymentMethod method = PaymentMethod.cash,
    DateTime? date,
  }) {
    final when = date ?? DateTime.now();
    final inv = Invoice(
      number: takeInvoiceNumber(),
      customerId: c.id,
      issueDate: when,
      dueDate: when,
      items: [InvoiceItem(name: note.isEmpty ? 'دفعة من العميل' : note, quantity: 1, unitPrice: amount)],
      payments: [Payment(amount: amount, date: when, method: method, note: note)],
    );
    upsert(invoices, inv);
    return inv;
  }

  // MARK: Staff & payroll

  Employee? employee(String? id) => id == null ? null : employees.items[id];

  List<Employee> get sortedEmployees => employees.all
    ..sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.name.compareTo(b.name);
    });

  List<SalaryAdjustment> adjustmentsOf(String employeeId, {String? periodKey}) =>
      adjustments.all
          .where((a) => a.employeeId == employeeId && (periodKey == null || a.periodKey == periodKey))
          .toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// The salary payment already recorded for [employeeId] in [periodKey], if any.
  Expense? salaryPayment(String employeeId, String periodKey) {
    for (final e in expenses.all) {
      if (e.employeeId == employeeId && e.periodKey == periodKey && e.adjustmentId == null) return e;
    }
    return null;
  }

  /// Every expense paid to an employee (salaries and advances), newest first.
  List<Expense> paymentsTo(String employeeId) =>
      expenses.all.where((e) => e.employeeId == employeeId).toList()..sort((a, b) => b.date.compareTo(a.date));

  Payslip payslip(Employee e, DateTime month) {
    final key = Fmt.monthKey(month);
    final adj = adjustmentsOf(e.id, periodKey: key);
    double sum(bool Function(SalaryAdjustment) test) => adj.where(test).fold(0.0, (s, a) => s + a.amount);
    return Payslip(
      employee: e,
      periodKey: key,
      base: e.salary,
      additions: sum((a) => a.type.sign > 0),
      deductions: sum((a) => a.type.sign < 0 && a.type != AdjustmentType.advance),
      advances: sum((a) => a.type == AdjustmentType.advance),
      adjustments: adj,
      payment: salaryPayment(e.id, key),
    );
  }

  /// Payslips for [month]: active employees plus anyone with activity that month.
  List<Payslip> payroll(DateTime month) {
    final key = Fmt.monthKey(month);
    return [
      for (final e in sortedEmployees)
        if (e.isActive || salaryPayment(e.id, key) != null || adjustmentsOf(e.id, periodKey: key).isNotEmpty)
          payslip(e, month),
    ];
  }

  /// Records the salary for [month] as an expense (category: salaries).
  Expense paySalary(Employee e, DateTime month, {DateTime? date, double? amount}) {
    final slip = payslip(e, month);
    final exp = slip.payment ?? Expense(employeeId: e.id, periodKey: slip.periodKey);
    exp
      ..title = 'مرتب ${e.name} - ${Fmt.month(month)}'
      ..amount = amount ?? slip.net
      ..category = ExpenseCategory.salaries
      ..customCategory = ''
      ..date = date ?? DateTime.now();
    upsert(expenses, exp);
    return exp;
  }

  /// Pays every active employee not paid yet for [month]. Returns how many.
  int payAllSalaries(DateTime month) {
    var n = 0;
    for (final slip in payroll(month)) {
      if (slip.isPaid || !slip.employee.isActive || slip.net <= 0) continue;
      paySalary(slip.employee, month);
      n++;
    }
    return n;
  }

  /// Saves a bonus/deduction. An advance is cash paid out now, so it also
  /// becomes an expense (and is later taken off the month's salary).
  void saveAdjustment(SalaryAdjustment a) {
    upsert(adjustments, a);
    final linked = expenses.all.where((e) => e.adjustmentId == a.id).firstOrNull;
    if (a.type == AdjustmentType.advance) {
      final name = employee(a.employeeId)?.name ?? '';
      final exp = linked ?? Expense(employeeId: a.employeeId, adjustmentId: a.id);
      exp
        ..title = 'سلفة $name${a.reason.isEmpty ? '' : ' - ${a.reason}'}'
        ..amount = a.amount
        ..category = ExpenseCategory.salaries
        ..customCategory = ''
        ..periodKey = a.periodKey
        ..date = a.date;
      upsert(expenses, exp);
    } else if (linked != null) {
      delete(expenses, linked.id);
    }
  }

  void deleteAdjustment(SalaryAdjustment a) {
    for (final e in expenses.all.where((e) => e.adjustmentId == a.id).toList()) {
      delete(expenses, e.id);
    }
    delete(adjustments, a.id);
  }

  /// Removes the employee and their pending bonuses/deductions.
  /// Money already paid (salaries, advances) stays in the expenses.
  void deleteEmployee(Employee e) {
    for (final a in adjustmentsOf(e.id)) {
      if (a.type != AdjustmentType.advance) delete(adjustments, a.id);
    }
    delete(employees, e.id);
  }

  double get monthlySalaries => employees.all.where((e) => e.isActive).fold(0.0, (s, e) => s + e.salary);

  // MARK: Fixed monthly expenses

  List<FixedExpense> get sortedFixedExpenses => fixedExpenses.all
    ..sort((a, b) {
      if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
      return a.dueDay.compareTo(b.dueDay);
    });

  double get monthlyFixedTotal => fixedExpenses.all.where((f) => f.isActive).fold(0.0, (s, f) => s + f.amount);

  Expense? fixedPayment(String fixedId, String periodKey) {
    for (final e in expenses.all) {
      if (e.fixedExpenseId == fixedId && e.periodKey == periodKey) return e;
    }
    return null;
  }

  /// Active fixed expenses not yet paid for [month].
  List<FixedExpense> unpaidFixed(DateTime month) {
    final key = Fmt.monthKey(month);
    return sortedFixedExpenses.where((f) => f.isActive && fixedPayment(f.id, key) == null).toList();
  }

  Expense payFixed(FixedExpense f, DateTime month, {double? amount, DateTime? date}) {
    final key = Fmt.monthKey(month);
    final exp = fixedPayment(f.id, key) ?? Expense(fixedExpenseId: f.id, periodKey: key);
    exp
      ..title = '${f.title} - ${Fmt.month(month)}'
      ..amount = amount ?? f.amount
      ..category = f.category
      ..customCategory = f.customCategory
      ..date = date ?? DateTime.now();
    upsert(expenses, exp);
    return exp;
  }

  /// Records every unpaid fixed expense that has a set amount. Returns the count.
  int payAllFixed(DateTime month) {
    var n = 0;
    for (final f in unpaidFixed(month)) {
      if (f.amount <= 0 || f.variable) continue;
      payFixed(f, month);
      n++;
    }
    return n;
  }

  /// What leaves the business every month no matter what: salaries + fixed bills.
  double get monthlyCommitments => monthlySalaries + monthlyFixedTotal;

  // MARK: Debts & follow-up

  /// Open debts in one direction, overdue / soonest due first.
  List<Debt> openDebts(DebtDirection direction) =>
      debts.all.where((d) => d.direction == direction && !d.isSettled).toList()..sort((a, b) {
        final ad = a.dueDate, bd = b.dueDate;
        if (ad == null && bd == null) return b.date.compareTo(a.date);
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });

  List<Debt> settledDebts() => debts.all.where((d) => d.isSettled).toList()..sort((a, b) => b.date.compareTo(a.date));

  void addDebtPayment(Debt d, double amount, {DateTime? date, String note = ''}) {
    d.payments.add(Payment(amount: amount, date: date, note: note));
    upsert(debts, d);
  }

  /// Clients who still owe money on issued invoices, biggest first.
  List<(Customer, double)> clientsWhoOwe() {
    final list = <(Customer, double)>[
      for (final c in customers.all)
        if (balanceOf(c.id) case final b when b > 0.009) (c, b),
    ];
    list.sort((a, b) => b.$2.compareTo(a.$2));
    return list;
  }

  /// Everything that needs following up as of [at]: bills and salaries due
  /// (in [at]'s month, up to that day) that aren't paid, money people owe
  /// me and money I owe.
  FollowUp followUp(DateTime at) {
    final key = Fmt.monthKey(at);
    final month = DateTime(at.year, at.month);
    return FollowUp(
      at: at,
      unpaidBills: [
        for (final f in sortedFixedExpenses)
          if (f.isActive && f.dueDay <= at.day && fixedPayment(f.id, key) == null) f,
      ],
      unpaidSalaries: [
        for (final p in payroll(month))
          if (p.employee.isActive && !p.isPaid && p.employee.payDay <= at.day && p.net > 0) p,
      ],
      clientsOwe: clientsWhoOwe(),
      owedToMe: openDebts(DebtDirection.owedToMe),
      iOwe: openDebts(DebtDirection.iOwe),
    );
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}

/// A client's money summary.
class ClientAccount {
  ClientAccount({
    required this.customer,
    required this.income,
    required this.invoiced,
    required this.spent,
    required this.balance,
  });

  final Customer customer;

  /// Money actually received.
  final double income;

  /// Total of issued invoices.
  final double invoiced;

  /// Money spent on this client.
  final double spent;

  /// Still owed by the client.
  final double balance;

  double get profit => income - spent;
  double get margin => income > 0 ? profit / income * 100 : 0;
}

/// Snapshot of what's unpaid and who owes whom, used by the commitments
/// screen and the periodic follow-up notification.
class FollowUp {
  FollowUp({
    required this.at,
    required this.unpaidBills,
    required this.unpaidSalaries,
    required this.clientsOwe,
    required this.owedToMe,
    required this.iOwe,
  });

  final DateTime at;
  final List<FixedExpense> unpaidBills;
  final List<Payslip> unpaidSalaries;
  final List<(Customer, double)> clientsOwe;
  final List<Debt> owedToMe;
  final List<Debt> iOwe;

  double get billsTotal => unpaidBills.fold(0.0, (s, f) => s + f.amount);
  double get salariesTotal => unpaidSalaries.fold(0.0, (s, p) => s + p.net);

  /// Money others owe me: client invoices + personal debts.
  double get owedToMeTotal => clientsOwe.fold(0.0, (s, c) => s + c.$2) + owedToMe.fold(0.0, (s, d) => s + d.remaining);
  int get owedToMeCount => clientsOwe.length + owedToMe.length;

  double get iOweTotal => iOwe.fold(0.0, (s, d) => s + d.remaining);

  /// What I still have to pay: bills, salaries and my debts.
  double get toPayTotal => billsTotal + salariesTotal + iOweTotal;

  bool get isEmpty =>
      unpaidBills.isEmpty && unpaidSalaries.isEmpty && clientsOwe.isEmpty && owedToMe.isEmpty && iOwe.isEmpty;

  /// Short multi-line text for a notification.
  String summary() {
    String names(Iterable<String> all) {
      final list = all.toList();
      final shown = list.take(3).join('، ');
      return list.length > 3 ? '$shown و${list.length - 3} كمان' : shown;
    }

    return [
      if (unpaidBills.isNotEmpty) '🧾 لسه ما اتدفعش: ${names(unpaidBills.map((f) => f.title))}',
      if (unpaidSalaries.isNotEmpty)
        '👥 لسه ما اخدش مرتبه: ${names(unpaidSalaries.map((p) => p.employee.name))} (${Fmt.money(salariesTotal)})',
      if (owedToMeCount > 0)
        '💵 ليك ${Fmt.money(owedToMeTotal)} عند: '
            '${names([...clientsOwe.map((c) => c.$1.name), ...owedToMe.map((d) => d.person)])}',
      if (iOwe.isNotEmpty) '💸 عليك ${Fmt.money(iOweTotal)} لـ: ${names(iOwe.map((d) => d.person))}',
    ].join('\n');
  }
}

/// One employee's salary for one month.
class Payslip {
  Payslip({
    required this.employee,
    required this.periodKey,
    required this.base,
    required this.additions,
    required this.deductions,
    required this.advances,
    required this.adjustments,
    this.payment,
  });

  final Employee employee;
  final String periodKey;
  final double base;

  /// Bonuses and overtime.
  final double additions;

  /// Deductions and absences.
  final double deductions;

  /// Advances already paid out during the month.
  final double advances;
  final List<SalaryAdjustment> adjustments;

  /// The salary expense, once paid.
  final Expense? payment;

  bool get isPaid => payment != null;

  /// What the employee earns for the month.
  double get gross => base + additions - deductions;

  /// What's left to hand over on pay day.
  double get net => gross - advances;
}
