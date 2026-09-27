import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'customers_screen.dart';
import 'expenses_screen.dart';
import 'invoices_screen.dart';

enum _Period { thisMonth, lastMonth, thisYear, all }

extension on _Period {
  String get label => switch (this) {
    _Period.thisMonth => 'هذا الشهر',
    _Period.lastMonth => 'الشهر الماضي',
    _Period.thisYear => 'هذا العام',
    _Period.all => 'الكل',
  };

  (DateTime?, DateTime?) get range {
    final now = DateTime.now();
    return switch (this) {
      _Period.thisMonth => (DateTime(now.year, now.month), null),
      _Period.lastMonth => (DateTime(now.year, now.month - 1), DateTime(now.year, now.month)),
      _Period.thisYear => (DateTime(now.year), null),
      _Period.all => (null, null),
    };
  }
}

/// Every client's money: what they paid, what you spent on them, profit, and what they owe.
class ClientAccountsScreen extends StatefulWidget {
  const ClientAccountsScreen({super.key});

  @override
  State<ClientAccountsScreen> createState() => _ClientAccountsScreenState();
}

class _ClientAccountsScreenState extends State<ClientAccountsScreen> {
  _Period _period = _Period.thisMonth;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final (from, to) = _period.range;
    final accounts = store.clientAccounts(from: from, to: to);
    final income = accounts.fold<double>(0, (s, a) => s + a.income);
    final spent = accounts.fold<double>(0, (s, a) => s + a.spent);
    final owed = accounts.fold<double>(0, (s, a) => s + a.balance);
    final now = DateTime.now();
    final subscribers = store.customers.all
        .where((c) => c.feeCycle == FeeCycle.monthly && c.fee > 0 && c.status != CustomerStatus.inactive)
        .toList();
    final monthlyExpected = subscribers.fold<double>(0, (s, c) => s + c.fee);
    final toBill = store.subscribersToBill(now);
    final unpaid = store.unpaidSubscriptions(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('حسابات العملاء'),
        actions: [
          IconButton(
            tooltip: 'الفواتير',
            icon: const Icon(Icons.receipt_long),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoicesScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-accounts',
        onPressed: () => showMoneyEntryMenu(context),
        icon: const Icon(Icons.add),
        label: const Text('تسجيل حركة'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ChipsBar<_Period>(
            options: _Period.values,
            selected: _period,
            label: (p) => p!.label,
            onSelected: (p) => setState(() => _period = p ?? _period),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: StatGrid(
              children: [
                StatCard(
                  title: 'المحصّل من العملاء',
                  value: Fmt.compactMoney(income),
                  icon: Icons.south_west,
                  color: Colors.green,
                ),
                StatCard(
                  title: 'المصروف على العملاء',
                  value: Fmt.compactMoney(spent),
                  icon: Icons.north_east,
                  color: Colors.red,
                ),
                StatCard(
                  title: 'صافي ربح العملاء',
                  value: Fmt.compactMoney(income - spent),
                  icon: Icons.trending_up,
                  color: income >= spent ? Colors.teal : Colors.red,
                  subtitle: income > 0 ? 'هامش ${Fmt.percent((income - spent) / income * 100)}' : null,
                ),
                StatCard(
                  title: 'مستحقات لم تُحصّل',
                  value: Fmt.compactMoney(owed),
                  icon: Icons.hourglass_bottom,
                  color: Colors.orange,
                ),
              ],
            ),
          ),
          if (subscribers.isNotEmpty) ...[
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: SectionCard(
                title: 'اشتراكات ${Fmt.month(now)}',
                icon: Icons.event_repeat,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${Fmt.number(subscribers.length)} مشترك • المتوقع شهرياً ${Fmt.money(monthlyExpected)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    if (toBill.isNotEmpty)
                      FilledButton.icon(
                        onPressed: () async {
                          final ok = await confirm(
                            context,
                            'إصدار فواتير الشهر؟',
                            'سيتم إصدار فاتورة اشتراك ${Fmt.month(now)} لـ ${Fmt.number(toBill.length)} عميل:\n'
                                '${toBill.map((c) => '• ${c.name}: ${Fmt.money(c.fee)}').join('\n')}',
                            action: 'إصدار',
                            destructive: false,
                          );
                          if (ok) {
                            final n = store.issueMonthlyInvoices(now);
                            if (context.mounted) toast(context, 'تم إصدار ${Fmt.number(n)} فاتورة');
                          }
                        },
                        icon: const Icon(Icons.receipt_long),
                        label: Text('إصدار فواتير الشهر (${Fmt.number(toBill.length)})'),
                      )
                    else
                      const Text('✅ كل فواتير الشهر صادرة'),
                    if (unpaid.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'لم يدفعوا بعد (${Fmt.number(unpaid.length)}):',
                        style: const TextStyle(color: Colors.orange),
                      ),
                      for (final u in unpaid)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Avatar(name: u.$1.name, color: u.$1.status.color, size: 32),
                          title: Text(u.$1.name),
                          subtitle: Text('يستحق ${Fmt.date(u.$2.dueDate)}'),
                          trailing: Text(
                            Fmt.money(u.$2.balance),
                            style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: u.$2.id)),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(
              'العملاء حسب الربح (${_period.label})',
              style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
            ),
          ),
          if (accounts.isEmpty)
            const EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'لا توجد حركات مالية',
              message: 'حدّد سعر لكل عميل، وسجّل الفلوس اللي بتستلمها منه واللي بتصرفها عليه من صفحة العميل',
            ),
          for (final a in accounts) ClientAccountTile(account: a),
        ],
      ),
    );
  }
}

class ClientAccountTile extends StatelessWidget {
  const ClientAccountTile({super.key, required this.account});
  final ClientAccount account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    final c = a.customer;
    final profitColor = a.profit >= 0 ? Colors.teal : Colors.red;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: c.id))),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Avatar(name: c.name, color: c.status.color, size: 36),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                        if (c.feeCycle != FeeCycle.none && c.fee > 0)
                          Text('${c.feeCycle.label}: ${Fmt.money(c.fee)}', style: const TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        Fmt.money(a.profit),
                        style: TextStyle(color: profitColor, fontWeight: FontWeight.bold),
                      ),
                      Text(a.income > 0 ? 'ربح ${Fmt.percent(a.margin)}' : 'ربح', style: const TextStyle(fontSize: 11)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _Amount('استلمت', a.income, Colors.green),
                  _Amount('صرفت', a.spent, Colors.red),
                  _Amount('عليه', a.balance, Colors.orange),
                ],
              ),
              if (a.income > 0) ...[
                const SizedBox(height: 6),
                LinearProgressIndicator(
                  value: (a.spent / a.income).clamp(0, 1),
                  color: Colors.red.shade300,
                  backgroundColor: Colors.green.shade100,
                  minHeight: 6,
                  borderRadius: BorderRadius.circular(6),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Amount extends StatelessWidget {
  const _Amount(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text(
          Fmt.compactMoney(value),
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13),
        ),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

/// "الحسابات" tab on a client's page: price, money in/out and every movement.
class ClientAccountTab extends StatelessWidget {
  const ClientAccountTab({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final c = customer;
    final now = DateTime.now();
    final month = store.accountOf(c, from: DateTime(now.year, now.month));
    final total = store.accountOf(c);

    // Timeline of money in (payments) and out (expenses).
    final moves = <_Move>[
      for (final inv in store.invoicesOf(c.id).where((i) => i.state == InvoiceState.issued))
        for (final p in inv.payments) _Move(p.date, p.amount, '${p.method.label} • ${inv.number}', true, invoice: inv),
      for (final e in store.expensesOf(c.id))
        _Move(e.date, e.amount, '${e.categoryLabel} • ${e.title}', false, expense: e),
    ]..sort((a, b) => b.date.compareTo(a.date));

    final monthInvoice = c.feeCycle == FeeCycle.monthly ? store.subscriptionInvoice(c.id, Fmt.monthKey(now)) : null;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        if (c.feeCycle != FeeCycle.none && c.fee > 0)
          Card(
            child: ListTile(
              leading: const Icon(Icons.sell),
              title: Text('${c.feeCycle.label}: ${Fmt.money(c.fee)}'),
              subtitle: c.feeCycle == FeeCycle.monthly
                  ? Text(
                      monthInvoice == null
                          ? 'فاتورة ${Fmt.month(now)} لم تصدر بعد'
                          : 'فاتورة ${Fmt.month(now)}: ${monthInvoice.status.label}',
                    )
                  : null,
              trailing: c.feeCycle == FeeCycle.monthly && monthInvoice == null
                  ? TextButton(
                      onPressed: () {
                        final inv = store.subscriptionInvoiceFor(c, now);
                        store.upsert(store.invoices, inv);
                        toast(context, 'تم إصدار فاتورة ${inv.number}');
                      },
                      child: const Text('إصدار'),
                    )
                  : null,
            ),
          )
        else
          Card(
            child: ListTile(
              leading: const Icon(Icons.sell_outlined),
              title: const Text('لم يتم تحديد سعر لهذا العميل'),
              subtitle: const Text('حدّد اشتراك شهري أو مبلغ ثابت من تعديل البيانات'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerFormScreen(customer: c))),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.green),
                onPressed: () => showReceiveMoneySheet(context, c),
                icon: const Icon(Icons.add_card),
                label: const Text('استلمت فلوس'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ExpenseFormScreen(customerId: c.id), fullscreenDialog: true),
                ),
                icon: const Icon(Icons.remove_circle_outline),
                label: const Text('صرفت عليه'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SummaryCard(title: 'هذا الشهر', account: month),
        _SummaryCard(title: 'من أول التعامل', account: total),
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
          child: Text(
            'الحركات المالية',
            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold),
          ),
        ),
        if (moves.isEmpty) const ListTile(title: Text('لا توجد حركات بعد')),
        for (final m in moves)
          ListTile(
            dense: true,
            leading: CircleAvatar(
              backgroundColor: (m.incoming ? Colors.green : Colors.red).withValues(alpha: 0.15),
              child: Icon(
                m.incoming ? Icons.south_west : Icons.north_east,
                color: m.incoming ? Colors.green : Colors.red,
                size: 18,
              ),
            ),
            title: Text(m.label, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(Fmt.date(m.date)),
            trailing: Text(
              '${m.incoming ? '+' : '-'} ${Fmt.money(m.amount)}',
              style: TextStyle(color: m.incoming ? Colors.green : Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () {
              if (m.invoice != null) {
                Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: m.invoice!.id)));
              } else if (m.expense != null) {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: m.expense), fullscreenDialog: true),
                );
              }
            },
          ),
      ],
    );
  }
}

class _Move {
  _Move(this.date, this.amount, this.label, this.incoming, {this.invoice, this.expense});
  final DateTime date;
  final double amount;
  final String label;
  final bool incoming;
  final Invoice? invoice;
  final Expense? expense;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.account});
  final String title;
  final ClientAccount account;

  @override
  Widget build(BuildContext context) {
    final a = account;
    Widget row(String label, double v, Color color, {bool bold = false}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
          ),
          Text(
            Fmt.money(v),
            style: TextStyle(color: color, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            row('فواتير صادرة', a.invoiced, Colors.blue),
            row('استلمت', a.income, Colors.green),
            row('صرفت عليه', a.spent, Colors.red),
            const Divider(),
            row(
              a.income > 0 ? 'صافي الربح (${Fmt.percent(a.margin)})' : 'صافي الربح',
              a.profit,
              a.profit >= 0 ? Colors.teal : Colors.red,
              bold: true,
            ),
            if (a.balance > 0) row('باقي عليه', a.balance, Colors.orange),
          ],
        ),
      ),
    );
  }
}

/// Quick "I received money from this client": pays open invoices first, the rest becomes a new paid invoice.
void showReceiveMoneySheet(BuildContext context, Customer c) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _ReceiveMoneySheet(customer: c),
  );
}

class _ReceiveMoneySheet extends StatefulWidget {
  const _ReceiveMoneySheet({required this.customer});
  final Customer customer;

  @override
  State<_ReceiveMoneySheet> createState() => _ReceiveMoneySheetState();
}

class _ReceiveMoneySheetState extends State<_ReceiveMoneySheet> {
  late final AppStore _store = context.read<AppStore>();
  late final List<Invoice> _open = _store.invoicesOf(widget.customer.id).where((i) => i.status.isOutstanding).toList()
    ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
  late double _amount = _open.isNotEmpty
      ? _open.fold(0.0, (s, i) => s + i.balance)
      : (widget.customer.feeCycle != FeeCycle.none ? widget.customer.fee : 0);
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  void _save() {
    if (_amount <= 0) {
      toast(context, 'اكتب المبلغ');
      return;
    }
    var left = _amount;
    // Settle the oldest open invoices first.
    for (final inv in _open) {
      if (left <= 0) break;
      final pay = left < inv.balance ? left : inv.balance;
      inv.payments.add(Payment(amount: pay, date: _date, method: _method, note: _note.text.trim()));
      _store.upsert(_store.invoices, inv);
      left -= pay;
    }
    if (left > 0.009) {
      _store.receiveMoney(widget.customer, left, note: _note.text.trim(), method: _method, date: _date);
    }
    Navigator.pop(context);
    toast(context, 'تم تسجيل ${Fmt.money(_amount)}');
  }

  @override
  Widget build(BuildContext context) {
    final owed = _open.fold<double>(0, (s, i) => s + i.balance);
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('استلمت فلوس من ${widget.customer.name}', style: Theme.of(context).textTheme.titleMedium),
          if (owed > 0)
            Text(
              'عليه ${Fmt.money(owed)} في ${Fmt.number(_open.length)} فاتورة، والمبلغ هيتخصم منها الأول',
              style: const TextStyle(fontSize: 12, color: Colors.orange),
            ),
          const SizedBox(height: 12),
          AmountField(label: 'المبلغ', value: _amount, suffix: Fmt.symbol, onChanged: (v) => _amount = v),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final m in PaymentMethod.values)
                ChoiceChip(
                  avatar: Icon(m.icon, size: 16),
                  label: Text(m.label),
                  selected: _method == m,
                  onSelected: (_) => setState(() => _method = m),
                ),
            ],
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(Fmt.date(_date)),
            onTap: () async {
              final d = await pickDate(context, _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          TextField(
            controller: _note,
            decoration: const InputDecoration(labelText: 'ملاحظة (مثال: دفعة مقدم)'),
          ),
          const SizedBox(height: 12),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}

/// Lets the user choose a client (with search).
Future<Customer?> pickCustomer(BuildContext context, {String title = 'اختر العميل'}) {
  return showModalBottomSheet<Customer>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _CustomerPicker(title: title),
  );
}

class _CustomerPicker extends StatefulWidget {
  const _CustomerPicker({required this.title});
  final String title;

  @override
  State<_CustomerPicker> createState() => _CustomerPickerState();
}

class _CustomerPickerState extends State<_CustomerPicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final list =
        store.customers.all
            .where((c) => _q.isEmpty || c.name.contains(_q) || c.sector.contains(_q) || c.contactPerson.contains(_q))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'ابحث باسم العميل'),
              onChanged: (v) => setState(() => _q = v.trim()),
            ),
          ),
          Expanded(
            child: list.isEmpty
                ? const EmptyState(
                    icon: Icons.people_outline,
                    title: 'لا يوجد عملاء',
                    message: 'أضف عميل الأول من تبويب العملاء',
                  )
                : ListView(
                    children: [
                      for (final c in list)
                        ListTile(
                          leading: Avatar(name: c.name, color: c.status.color, size: 38),
                          title: Text(c.name),
                          subtitle: c.sector.isEmpty ? null : Text(c.sector),
                          onTap: () => Navigator.pop(context, c),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

/// Quick menu to record any money movement.
Future<void> showMoneyEntryMenu(BuildContext context) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.green,
              child: Icon(Icons.south_west, color: Colors.white),
            ),
            title: const Text('استلمت فلوس من عميل'),
            onTap: () => Navigator.pop(ctx, 'in'),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.red,
              child: Icon(Icons.north_east, color: Colors.white),
            ),
            title: const Text('صرفت على عميل'),
            subtitle: const Text('إعلانات، فريلانسر، طباعة، مواصلات...'),
            onTap: () => Navigator.pop(ctx, 'out'),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.brown,
              child: Icon(Icons.business, color: Colors.white),
            ),
            title: const Text('مصروف عام للشغل'),
            subtitle: const Text('إيجار، رواتب، إنترنت...'),
            onTap: () => Navigator.pop(ctx, 'general'),
          ),
          ListTile(
            leading: const CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(Icons.receipt_long, color: Colors.white),
            ),
            title: const Text('فاتورة جديدة لعميل'),
            onTap: () => Navigator.pop(ctx, 'invoice'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
  if (choice == null || !context.mounted) return;
  switch (choice) {
    case 'in':
      final c = await pickCustomer(context, title: 'استلمت فلوس من مين؟');
      if (c != null && context.mounted) showReceiveMoneySheet(context, c);
    case 'out':
      final c = await pickCustomer(context, title: 'صرفت على مين؟');
      if (c != null && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ExpenseFormScreen(customerId: c.id), fullscreenDialog: true),
        );
      }
    case 'general':
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const ExpenseFormScreen(), fullscreenDialog: true),
      );
    case 'invoice':
      final c = await pickCustomer(context, title: 'فاتورة لمين؟');
      if (c != null && context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => InvoiceFormScreen(customerId: c.id), fullscreenDialog: true),
        );
      }
  }
}
