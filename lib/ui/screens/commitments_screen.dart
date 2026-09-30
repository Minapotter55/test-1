import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/contact_actions.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'customers_screen.dart';
import 'fixed_expenses_screen.dart';
import 'payroll_screen.dart';
import 'reminders_screen.dart';

/// One place to follow up: which bills and salaries are paid this month,
/// who owes me money and whom I owe.
class CommitmentsScreen extends StatefulWidget {
  const CommitmentsScreen({super.key});

  @override
  State<CommitmentsScreen> createState() => _CommitmentsScreenState();
}

class _CommitmentsScreenState extends State<CommitmentsScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);
  bool _showSettled = false;

  void _push(Widget page, {bool dialog = false}) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => page, fullscreenDialog: dialog));

  Future<void> _addDebt() async {
    final dir = await showModalBottomSheet<DebtDirection>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final d in DebtDirection.values)
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: d.color.withValues(alpha: 0.15),
                  child: Icon(d.icon, color: d.color),
                ),
                title: Text(d == DebtDirection.owedToMe ? 'حد عليه فلوس ليّا' : 'أنا عليّا فلوس لحد'),
                subtitle: Text(
                  d == DebtDirection.owedToMe
                      ? 'سلفة، باقي حساب، فلوس لسه ما اتحصلتش'
                      : 'مورد، فريلانسر، صاحب المكان، قسط...',
                ),
                onTap: () => Navigator.pop(ctx, d),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (dir != null && mounted) _push(DebtFormScreen(direction: dir), dialog: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;
    final isPast = _month.isBefore(DateTime(now.year, now.month));
    final key = Fmt.monthKey(_month);
    // For the current month: what's due up to today. For a past month: all of it.
    final asOf = isCurrent ? now : DateTime(_month.year, _month.month, 28, 23);
    final follow = store.followUp(asOf);

    final bills = store.sortedFixedExpenses.where((f) => f.isActive || store.fixedPayment(f.id, key) != null).toList();
    final slips = store.payroll(_month);
    final billsLeft = bills.where((f) => store.fixedPayment(f.id, key) == null).fold(0.0, (s, f) => s + f.amount);
    final salariesLeft = slips.where((p) => !p.isPaid && p.employee.isActive).fold(0.0, (s, p) => s + p.net);
    final overdueCount = isCurrent || isPast ? follow.unpaidBills.length + follow.unpaidSalaries.length : 0;
    final settled = store.settledDebts();

    return Scaffold(
      appBar: AppBar(
        title: const Text('الالتزامات والمتابعة'),
        actions: [
          IconButton(
            tooltip: 'إعدادات التذكير',
            onPressed: () => _push(const RemindersScreen()),
            icon: const Icon(Icons.notifications_active_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-commitments',
        onPressed: _addDebt,
        icon: const Icon(Icons.add),
        label: const Text('ليك / عليك فلوس'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          StatGrid(
            children: [
              StatCard(
                title: 'باقي تدفعه الشهر ده',
                value: Fmt.money(billsLeft + salariesLeft),
                icon: Icons.hourglass_bottom,
                color: Colors.orange,
                subtitle: overdueCount > 0 ? '${Fmt.number(overdueCount)} فات ميعادهم' : null,
              ),
              StatCard(
                title: 'عليك للناس',
                value: Fmt.money(follow.iOweTotal),
                icon: DebtDirection.iOwe.icon,
                color: Colors.red,
                subtitle: follow.iOwe.isEmpty ? 'مفيش' : '${Fmt.number(follow.iOwe.length)} شخص',
              ),
              StatCard(
                title: 'ليك عند الناس',
                value: Fmt.money(follow.owedToMeTotal),
                icon: DebtDirection.owedToMe.icon,
                color: Colors.green,
                subtitle: follow.owedToMeCount == 0 ? 'مفيش' : '${Fmt.number(follow.owedToMeCount)} شخص / عميل',
              ),
              StatCard(
                title: 'الالتزامات الشهرية',
                value: Fmt.money(store.monthlyCommitments),
                icon: Icons.event_repeat,
                color: Colors.indigo,
                subtitle: 'ثابت + مرتبات',
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Fixed bills
          SectionCard(
            title: 'المصاريف الثابتة (إيجار، كهرباء...)',
            icon: Icons.home_work,
            trailing: TextButton(onPressed: () => _push(const FixedExpensesScreen()), child: const Text('الكل')),
            child: bills.isEmpty
                ? _EmptyHint(
                    text: 'ضيف الإيجار والكهرباء والمياه والنت وأي حاجة بتدفعها كل شهر',
                    action: 'إضافة مصروف ثابت',
                    onTap: () => _push(const FixedExpensesScreen()),
                  )
                : Column(
                    children: [
                      for (final f in bills)
                        _StatusRow(
                          icon: fixedIcon(f),
                          color: f.category.color,
                          title: f.title,
                          subtitle: 'يوم ${Fmt.number(f.dueDay)}${f.variable ? ' • مبلغ متغير' : ''}',
                          amount: store.fixedPayment(f.id, key)?.amount ?? f.amount,
                          done: store.fixedPayment(f.id, key) != null,
                          doneLabel: 'اتدفع',
                          late: (isPast || (isCurrent && now.day > f.dueDay)) && store.fixedPayment(f.id, key) == null,
                          actionLabel: 'دفعت',
                          onAction: () async {
                            final amount = await askAmount(
                              context,
                              'دفع ${f.title} - ${Fmt.month(_month)}',
                              initial: f.amount,
                              hint: f.variable ? 'اكتب قيمة الفاتورة' : null,
                            );
                            if (amount == null || !context.mounted) return;
                            context.read<AppStore>().payFixed(f, _month, amount: amount);
                          },
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // Salaries
          SectionCard(
            title: 'المرتبات: مين اخد ومين لأ',
            icon: Icons.badge,
            trailing: TextButton(onPressed: () => _push(const PayrollScreen()), child: const Text('الكل')),
            child: slips.isEmpty
                ? _EmptyHint(
                    text: 'ضيف الموظفين بمرتباتهم وتابع مين قبض كل شهر',
                    action: 'إضافة موظف',
                    onTap: () => _push(const PayrollScreen()),
                  )
                : Column(
                    children: [
                      for (final p in slips)
                        _StatusRow(
                          avatar: p.employee.name,
                          title: p.employee.name,
                          subtitle: [
                            'يوم ${Fmt.number(p.employee.payDay)}',
                            if (p.deductions > 0) 'خصم ${Fmt.money(p.deductions)}',
                            if (p.advances > 0) 'سلف ${Fmt.money(p.advances)}',
                          ].join(' • '),
                          amount: p.isPaid ? p.payment!.amount : p.net,
                          done: p.isPaid,
                          doneLabel: 'اخد',
                          late: !p.isPaid && (isPast || (isCurrent && now.day > p.employee.payDay)),
                          actionLabel: 'صرف',
                          onTap: () => _push(EmployeeDetailScreen(employeeId: p.employee.id, month: _month)),
                          onAction: () async {
                            final amount = await askAmount(context, 'صرف مرتب ${p.employee.name}', initial: p.net);
                            if (amount == null || !context.mounted) return;
                            context.read<AppStore>().paySalary(p.employee, _month, amount: amount);
                          },
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // Owed to me
          SectionCard(
            title: 'ليك فلوس عند',
            icon: DebtDirection.owedToMe.icon,
            trailing: Text(
              Fmt.money(follow.owedToMeTotal),
              style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
            ),
            child: follow.owedToMeCount == 0
                ? const Text('مفيش حد عليه فلوس ليك دلوقتي 👌')
                : Column(
                    children: [
                      for (final (c, balance) in follow.clientsOwe)
                        _StatusRow(
                          avatar: c.name,
                          title: c.name,
                          subtitle: 'عميل • فواتير لسه ما اتدفعتش',
                          amount: balance,
                          amountColor: Colors.green,
                          onTap: () => _push(CustomerDetailScreen(id: c.id)),
                        ),
                      for (final d in follow.owedToMe) _DebtRow(debt: d),
                    ],
                  ),
          ),
          const SizedBox(height: 12),

          // I owe
          SectionCard(
            title: 'عليك فلوس لـ',
            icon: DebtDirection.iOwe.icon,
            trailing: Text(
              Fmt.money(follow.iOweTotal),
              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            child: follow.iOwe.isEmpty
                ? const Text('مش عليك فلوس لحد ✅')
                : Column(children: [for (final d in follow.iOwe) _DebtRow(debt: d)]),
          ),
          if (settled.isNotEmpty) ...[
            const SizedBox(height: 4),
            TextButton.icon(
              onPressed: () => setState(() => _showSettled = !_showSettled),
              icon: Icon(_showSettled ? Icons.expand_less : Icons.expand_more),
              label: Text('حسابات اتقفلت (${Fmt.number(settled.length)})'),
            ),
            if (_showSettled)
              Card(
                child: Column(children: [for (final d in settled) _DebtRow(debt: d)]),
              ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text, required this.action, required this.onTap});
  final String text;
  final String action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(text),
        TextButton.icon(onPressed: onTap, icon: const Icon(Icons.add), label: Text(action)),
      ],
    );
  }
}

/// A row with a paid / not-paid state and an optional quick action.
class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    this.icon,
    this.color,
    this.avatar,
    this.done,
    this.doneLabel = '',
    this.late = false,
    this.actionLabel,
    this.onAction,
    this.onTap,
    this.amountColor,
  });

  final String title;
  final String subtitle;
  final double amount;
  final IconData? icon;
  final Color? color;
  final String? avatar;

  /// null = no status (just an amount).
  final bool? done;
  final String doneLabel;
  final bool late;
  final String? actionLabel;
  final VoidCallback? onAction;
  final VoidCallback? onTap;
  final Color? amountColor;

  @override
  Widget build(BuildContext context) {
    final c = color ?? Theme.of(context).colorScheme.primary;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      onTap: onTap,
      leading: avatar != null
          ? Avatar(name: avatar!, size: 38)
          : CircleAvatar(
              radius: 19,
              backgroundColor: c.withValues(alpha: 0.15),
              child: Icon(icon, color: c, size: 20),
            ),
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        late ? '$subtitle • متأخر' : subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: late ? const TextStyle(color: Colors.red) : null,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            Fmt.money(amount),
            style: TextStyle(fontWeight: FontWeight.bold, color: amountColor),
          ),
          if (done == true)
            Pill(doneLabel, color: Colors.green, icon: Icons.check)
          else if (done == false && onAction != null)
            SizedBox(
              height: 26,
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  visualDensity: VisualDensity.compact,
                  backgroundColor: late ? Colors.red.withValues(alpha: 0.15) : null,
                  foregroundColor: late ? Colors.red : null,
                ),
                onPressed: onAction,
                child: Text(actionLabel ?? '', style: const TextStyle(fontSize: 12)),
              ),
            ),
        ],
      ),
    );
  }
}

class _DebtRow extends StatelessWidget {
  const _DebtRow({required this.debt});
  final Debt debt;

  @override
  Widget build(BuildContext context) {
    final d = debt;
    return _StatusRow(
      icon: d.direction.icon,
      color: d.direction.color,
      title: d.person,
      subtitle: [
        if (d.reason.isNotEmpty) d.reason,
        if (d.isSettled)
          'اتقفل'
        else if (d.dueDate != null)
          'الميعاد ${Fmt.date(d.dueDate!)}'
        else
          'من ${Fmt.date(d.date)}',
        if (d.paid > 0 && !d.isSettled) 'اتدفع ${Fmt.money(d.paid)}',
      ].join(' • '),
      amount: d.isSettled ? d.amount : d.remaining,
      amountColor: d.isSettled ? null : d.direction.color,
      late: d.isOverdue,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DebtDetailScreen(id: d.id))),
    );
  }
}

class DebtDetailScreen extends StatelessWidget {
  const DebtDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final d = store.debts.items[id];
    if (d == null) return const Scaffold(body: Center(child: Text('الحساب ده اتحذف')));
    final mine = d.direction == DebtDirection.owedToMe;

    return Scaffold(
      appBar: AppBar(
        title: Text(d.person),
        actions: [
          if (d.phone.isNotEmpty) ...[
            IconButton(
              tooltip: 'واتساب',
              onPressed: () {
                final text = mine
                    ? 'أهلاً ${d.person}، بفكّرك بالمبلغ المتبقي ${Fmt.money(d.remaining)}${d.reason.isEmpty ? '' : ' (${d.reason})'}. شكراً 🙏'
                    : '';
                ContactActions.open(ContactActions.whatsapp(d.phone, store.business.countryCode, text: text));
              },
              icon: const Icon(Icons.chat),
            ),
            IconButton(
              tooltip: 'اتصال',
              onPressed: () => ContactActions.open(ContactActions.call(d.phone)),
              icon: const Icon(Icons.call),
            ),
          ],
          IconButton(
            tooltip: 'تعديل',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => DebtFormScreen(debt: d), fullscreenDialog: true),
            ),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Pill(d.direction.label, color: d.direction.color, icon: d.direction.icon),
                  const SizedBox(height: 10),
                  Text(
                    d.isSettled ? 'اتقفل ✅' : Fmt.money(d.remaining),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: d.isSettled ? Colors.green : d.direction.color),
                  ),
                  Text(d.isSettled ? 'الحساب خلص' : (mine ? 'باقي ليك' : 'باقي عليك')),
                  const SizedBox(height: 12),
                  MoneyRow('المبلغ الأصلي', d.amount),
                  MoneyRow('اتدفع منه', d.paid, color: Colors.green),
                  if (d.dueDate != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          const Expanded(child: Text('الميعاد')),
                          Text(
                            Fmt.date(d.dueDate!),
                            style: TextStyle(color: d.isOverdue ? Colors.red : null, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  if (d.reason.isNotEmpty) ...[
                    const Divider(),
                    Align(alignment: AlignmentDirectional.centerStart, child: Text(d.reason)),
                  ],
                ],
              ),
            ),
          ),
          if (!d.isSettled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () async {
                      final amount = await askAmount(
                        context,
                        mine ? 'استلمت كام؟' : 'دفعت كام؟',
                        initial: d.remaining,
                        hint: 'تقدر تكتب جزء من المبلغ',
                      );
                      if (amount == null || !context.mounted) return;
                      context.read<AppStore>().addDebtPayment(d, amount.clamp(0, d.remaining).toDouble());
                    },
                    icon: const Icon(Icons.payments),
                    label: Text(mine ? 'استلمت جزء / الكل' : 'دفعت جزء / الكل'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => context.read<AppStore>().addDebtPayment(d, d.remaining, note: 'تقفيل الحساب'),
                  child: const Text('اتقفل'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'الدفعات',
            icon: Icons.history,
            child: d.payments.isEmpty
                ? const Text('لسه مفيش دفعات')
                : Column(
                    children: [
                      for (final p in d.payments.reversed)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Icons.check_circle, color: Colors.green),
                          title: Text(Fmt.money(p.amount)),
                          subtitle: Text([Fmt.date(p.date), if (p.note.isNotEmpty) p.note].join(' • ')),
                          trailing: IconButton(
                            tooltip: 'حذف الدفعة',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              if (await confirm(context, 'حذف الدفعة؟', Fmt.money(p.amount))) {
                                d.payments.remove(p);
                                store.upsert(store.debts, d);
                              }
                            },
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class DebtFormScreen extends StatefulWidget {
  const DebtFormScreen({super.key, this.debt, this.direction = DebtDirection.owedToMe});
  final Debt? debt;
  final DebtDirection direction;

  @override
  State<DebtFormScreen> createState() => _DebtFormScreenState();
}

class _DebtFormScreenState extends State<DebtFormScreen> {
  late final Debt? _d = widget.debt;
  late final _person = TextEditingController(text: _d?.person);
  late final _phone = TextEditingController(text: _d?.phone);
  late final _reason = TextEditingController(text: _d?.reason);
  late DebtDirection _dir = _d?.direction ?? widget.direction;
  late double _amount = _d?.amount ?? 0;
  late DateTime _date = _d?.date ?? DateTime.now();
  late DateTime? _due = _d?.dueDate;

  @override
  void dispose() {
    _person.dispose();
    _phone.dispose();
    _reason.dispose();
    super.dispose();
  }

  void _save() {
    if (_person.text.trim().isEmpty || _amount <= 0) {
      toast(context, 'اكتب الاسم والمبلغ');
      return;
    }
    final store = context.read<AppStore>();
    final d = _d ?? Debt();
    d
      ..person = _person.text.trim()
      ..phone = _phone.text.trim()
      ..reason = _reason.text.trim()
      ..direction = _dir
      ..amount = _amount
      ..date = _date
      ..dueDate = _due;
    store.upsert(store.debts, d);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_d == null ? 'حساب جديد' : 'تعديل الحساب'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<DebtDirection>(
            segments: [
              for (final d in DebtDirection.values) ButtonSegment(value: d, icon: Icon(d.icon), label: Text(d.label)),
            ],
            selected: {_dir},
            onSelectionChanged: (s) => setState(() => _dir = s.first),
          ),
          gap,
          TextField(
            controller: _person,
            decoration: InputDecoration(
              labelText: 'الاسم *',
              hintText: _dir == DebtDirection.owedToMe ? 'مين اللي عليه الفلوس؟' : 'مين اللي ليه الفلوس؟',
              prefixIcon: const Icon(Icons.person),
            ),
          ),
          gap,
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'التليفون (للتذكير على واتساب)',
              prefixIcon: Icon(Icons.phone),
            ),
          ),
          gap,
          AmountField(label: 'المبلغ *', value: _amount, suffix: Fmt.symbol, onChanged: (v) => _amount = v),
          gap,
          TextField(
            controller: _reason,
            decoration: const InputDecoration(
              labelText: 'السبب',
              hintText: 'مثال: سلفة / باقي حساب تصوير / قسط الكاميرا',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text('التاريخ: ${Fmt.date(_date)}'),
            onTap: () async {
              final d = await pickDate(context, _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.alarm),
            title: Text(_due == null ? 'ميعاد السداد (اختياري)' : 'ميعاد السداد: ${Fmt.date(_due!)}'),
            subtitle: const Text('هيجيلك إشعار يوم الميعاد وكل أسبوع بعده لحد ما يتقفل'),
            trailing: _due == null
                ? null
                : IconButton(onPressed: () => setState(() => _due = null), icon: const Icon(Icons.clear)),
            onTap: () async {
              final d = await pickDate(context, _due ?? DateTime.now().add(const Duration(days: 7)));
              if (d != null) setState(() => _due = d);
            },
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_d != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف الحساب؟', _d.person)) {
                  if (!context.mounted) return;
                  final store = context.read<AppStore>();
                  store.delete(store.debts, _d.id);
                  Navigator.of(context)
                    ..pop()
                    ..maybePop();
                }
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
