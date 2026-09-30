import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';

/// Arrows to move between months.
class MonthSwitcher extends StatelessWidget {
  const MonthSwitcher({super.key, required this.month, required this.onChanged});
  final DateTime month;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          tooltip: 'الشهر السابق',
          onPressed: () => onChanged(DateTime(month.year, month.month - 1)),
          icon: const Icon(Icons.chevron_right),
        ),
        Text(Fmt.month(month), style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        IconButton(
          tooltip: 'الشهر التالي',
          onPressed: () => onChanged(DateTime(month.year, month.month + 1)),
          icon: const Icon(Icons.chevron_left),
        ),
      ],
    );
  }
}

/// A label / amount row used in payslip summaries.
class MoneyRow extends StatelessWidget {
  const MoneyRow(this.label, this.amount, {super.key, this.color, this.bold = false, this.sign = ''});
  final String label;
  final double amount;
  final Color? color;
  final bool bold;
  final String sign;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(fontWeight: bold ? FontWeight.bold : FontWeight.normal, color: color);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('$sign${Fmt.money(amount)}', style: style),
        ],
      ),
    );
  }
}

/// Employees and the monthly payroll.
class PayrollScreen extends StatefulWidget {
  const PayrollScreen({super.key});

  @override
  State<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends State<PayrollScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _openForm([Employee? e]) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: e), fullscreenDialog: true),
  );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final slips = store.payroll(_month);
    final total = slips.fold(0.0, (s, p) => s + p.gross);
    final paid = slips.where((p) => p.isPaid).fold(0.0, (s, p) => s + p.payment!.amount + p.advances);
    final toPay = slips.where((p) => !p.isPaid && p.employee.isActive).fold(0.0, (s, p) => s + p.net);
    final unpaidCount = slips.where((p) => !p.isPaid && p.employee.isActive && p.net > 0).length;
    final inactive = store.sortedEmployees.where((e) => !e.isActive && !slips.any((p) => p.employee.id == e.id));

    return Scaffold(
      appBar: AppBar(title: const Text('الموظفين والمرتبات')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-payroll',
        onPressed: _openForm,
        icon: const Icon(Icons.person_add),
        label: const Text('موظف جديد'),
      ),
      body: store.employees.items.isEmpty
          ? EmptyState(
              icon: Icons.badge_outlined,
              title: 'لا يوجد موظفين',
              message: 'ضيف فريقك بمرتب كل واحد، وسجّل الخصومات والمكافآت والسلف، واصرف المرتبات آخر الشهر',
              actionLabel: 'إضافة موظف',
              onAction: _openForm,
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: [
                MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                StatGrid(
                  children: [
                    StatCard(
                      title: 'مرتبات الشهر',
                      value: Fmt.money(total),
                      icon: Icons.payments,
                      color: Colors.indigo,
                      subtitle: '${Fmt.number(slips.length)} موظف',
                    ),
                    StatCard(title: 'اتصرف', value: Fmt.money(paid), icon: Icons.check_circle, color: Colors.green),
                    StatCard(
                      title: 'باقي يتصرف',
                      value: Fmt.money(toPay),
                      icon: Icons.hourglass_bottom,
                      color: Colors.orange,
                      subtitle: unpaidCount > 0 ? '${Fmt.number(unpaidCount)} موظف' : 'كله اتصرف ✅',
                    ),
                    StatCard(
                      title: 'خصومات الشهر',
                      value: Fmt.money(slips.fold(0.0, (s, p) => s + p.deductions)),
                      icon: Icons.remove_circle_outline,
                      color: Colors.red,
                      subtitle: 'مكافآت: ${Fmt.money(slips.fold(0.0, (s, p) => s + p.additions))}',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (unpaidCount > 0)
                  FilledButton.icon(
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        'صرف مرتبات ${Fmt.month(_month)}',
                        'هيتسجل ${Fmt.money(toPay)} مصروف مرتبات لـ ${Fmt.number(unpaidCount)} موظف (بعد الخصومات والسلف)',
                        action: 'صرف',
                        destructive: false,
                      );
                      if (!ok || !context.mounted) return;
                      final n = context.read<AppStore>().payAllSalaries(_month);
                      toast(context, 'تم صرف مرتبات ${Fmt.number(n)} موظف ✅');
                    },
                    icon: const Icon(Icons.price_check),
                    label: const Text('صرف كل المرتبات'),
                  ),
                const SizedBox(height: 6),
                for (final p in slips)
                  _PayslipTile(
                    slip: p,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => EmployeeDetailScreen(employeeId: p.employee.id, month: _month),
                      ),
                    ),
                  ),
                if (inactive.isNotEmpty) ...[
                  const Padding(
                    padding: EdgeInsets.fromLTRB(4, 16, 4, 4),
                    child: Text('موظفين سابقين', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final e in inactive)
                    Card(
                      child: ListTile(
                        leading: Avatar(name: e.name, color: Colors.grey),
                        title: Text(e.name),
                        subtitle: Text(e.jobTitle),
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => EmployeeDetailScreen(employeeId: e.id, month: _month),
                          ),
                        ),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}

class _PayslipTile extends StatelessWidget {
  const _PayslipTile({required this.slip, required this.onTap});
  final Payslip slip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final e = slip.employee;
    final details = [
      if (slip.additions > 0) '+${Fmt.money(slip.additions)}',
      if (slip.deductions > 0) 'خصم ${Fmt.money(slip.deductions)}',
      if (slip.advances > 0) 'سلف ${Fmt.money(slip.advances)}',
    ];
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Avatar(name: e.name, color: e.isActive ? null : Colors.grey),
        title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          [if (e.jobTitle.isNotEmpty) e.jobTitle, 'الأساسي ${Fmt.money(slip.base)}', ...details].join(' • '),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              Fmt.money(slip.isPaid ? slip.payment!.amount : slip.net),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            slip.isPaid
                ? const Pill('اتصرف', color: Colors.green, icon: Icons.check)
                : Pill('يوم ${Fmt.number(e.payDay)}', color: Colors.orange, icon: Icons.schedule),
          ],
        ),
      ),
    );
  }
}

class EmployeeDetailScreen extends StatefulWidget {
  const EmployeeDetailScreen({super.key, required this.employeeId, required this.month});
  final String employeeId;
  final DateTime month;

  @override
  State<EmployeeDetailScreen> createState() => _EmployeeDetailScreenState();
}

class _EmployeeDetailScreenState extends State<EmployeeDetailScreen> {
  late DateTime _month = widget.month;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final e = store.employee(widget.employeeId);
    if (e == null) return const Scaffold(body: Center(child: Text('الموظف اتحذف')));
    final slip = store.payslip(e, _month);
    final history = store.paymentsTo(e.id);
    final yearStart = DateTime(_month.year);
    final paidThisYear = history.where((x) => !x.date.isBefore(yearStart)).fold(0.0, (s, x) => s + x.amount);

    return Scaffold(
      appBar: AppBar(
        title: Text(e.name),
        actions: [
          if (e.phone.isNotEmpty)
            IconButton(
              tooltip: 'اتصال',
              onPressed: () => launchUrl(Uri(scheme: 'tel', path: e.phone)),
              icon: const Icon(Icons.call),
            ),
          IconButton(
            tooltip: 'تعديل',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => EmployeeFormScreen(employee: e), fullscreenDialog: true),
            ),
            icon: const Icon(Icons.edit),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-adjustment',
        onPressed: () => showAdjustmentSheet(context, e, _month),
        icon: const Icon(Icons.add),
        label: const Text('خصم / مكافأة / سلفة'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
        children: [
          Card(
            child: ListTile(
              leading: Avatar(name: e.name, color: e.isActive ? null : Colors.grey),
              title: Text(e.jobTitle.isEmpty ? 'موظف' : e.jobTitle),
              subtitle: Text(
                [
                  'المرتب ${Fmt.money(e.salary)}',
                  'بيقبض يوم ${Fmt.number(e.payDay)}',
                  if (e.hireDate != null) 'من ${Fmt.date(e.hireDate!)}',
                  if (!e.isActive) 'مش شغال حالياً',
                ].join(' • '),
              ),
            ),
          ),
          MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
          SectionCard(
            title: 'مرتب ${Fmt.month(_month)}',
            icon: Icons.receipt,
            trailing: slip.isPaid ? const Pill('اتصرف', color: Colors.green, icon: Icons.check) : null,
            child: Column(
              children: [
                MoneyRow('المرتب الأساسي', slip.base),
                if (slip.additions > 0) MoneyRow('مكافآت وإضافي', slip.additions, color: Colors.green, sign: '+ '),
                if (slip.deductions > 0) MoneyRow('خصومات وغياب', slip.deductions, color: Colors.red, sign: '- '),
                const Divider(),
                MoneyRow('المستحق عن الشهر', slip.gross, bold: true),
                if (slip.advances > 0)
                  MoneyRow('سلف اتصرفت خلال الشهر', slip.advances, color: Colors.purple, sign: '- '),
                MoneyRow(
                  slip.isPaid ? 'اتصرف له يوم ${Fmt.date(slip.payment!.date)}' : 'الباقي يتسلم',
                  slip.isPaid ? slip.payment!.amount : slip.net,
                  bold: true,
                  color: slip.isPaid ? Colors.green : Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 10),
                if (!slip.isPaid)
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () async {
                        final amount = await askAmount(
                          context,
                          'صرف مرتب ${e.name}',
                          initial: slip.net,
                          hint: 'تقدر تعدّل المبلغ لو صرفت رقم مختلف',
                        );
                        if (amount == null || !context.mounted) return;
                        context.read<AppStore>().paySalary(e, _month, amount: amount);
                        toast(context, 'اتسجل صرف المرتب ✅');
                      },
                      icon: const Icon(Icons.price_check),
                      label: Text('صرف ${Fmt.money(slip.net)}'),
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () async {
                      if (await confirm(context, 'إلغاء الصرف؟', 'هيتشال مصروف المرتب ده من الحسابات')) {
                        if (!context.mounted) return;
                        final store = context.read<AppStore>();
                        store.delete(store.expenses, slip.payment!.id);
                      }
                    },
                    icon: const Icon(Icons.undo),
                    label: const Text('إلغاء الصرف'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'الخصومات والمكافآت والسلف',
            icon: Icons.tune,
            child: slip.adjustments.isEmpty
                ? const Text('مفيش حاجة الشهر ده. دوس الزرار تحت عشان تضيف.')
                : Column(
                    children: [
                      for (final a in slip.adjustments)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(a.type.icon, color: a.type.color),
                          title: Text(a.reason.isEmpty ? a.type.label : '${a.type.label}: ${a.reason}'),
                          subtitle: Text(Fmt.date(a.date)),
                          trailing: Text(
                            '${a.type.sign > 0 ? '+' : '-'}${Fmt.money(a.amount)}',
                            style: TextStyle(color: a.type.color, fontWeight: FontWeight.bold),
                          ),
                          onTap: () => showAdjustmentSheet(context, e, _month, existing: a),
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 10),
          SectionCard(
            title: 'سجل القبض',
            icon: Icons.history,
            trailing: Text('السنة دي: ${Fmt.money(paidThisYear)}', style: const TextStyle(fontSize: 12)),
            child: history.isEmpty
                ? const Text('لسه مفيش مرتبات اتصرفت')
                : Column(
                    children: [
                      for (final x in history.take(24))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(x.adjustmentId != null ? Icons.payments : Icons.price_check),
                          title: Text(x.title),
                          subtitle: Text(Fmt.date(x.date)),
                          trailing: Text(Fmt.money(x.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
          ),
          if (e.notes.isNotEmpty || e.customFields.isNotEmpty) ...[
            const SizedBox(height: 10),
            SectionCard(
              title: 'بيانات إضافية',
              icon: Icons.info_outline,
              child: Column(
                children: [
                  InfoTile('التليفون', e.phone, icon: Icons.phone),
                  for (final f in e.customFields) InfoTile(f.key, f.value, icon: Icons.label_outline),
                  InfoTile('ملاحظات', e.notes, icon: Icons.notes),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Small dialog for entering an amount.
Future<double?> askAmount(BuildContext context, String title, {double initial = 0, String? hint}) {
  var value = initial;
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AmountField(label: 'المبلغ', value: initial, suffix: Fmt.symbol, onChanged: (v) => value = v),
          if (hint != null) ...[const SizedBox(height: 8), Text(hint, style: Theme.of(ctx).textTheme.bodySmall)],
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
        FilledButton(onPressed: () => Navigator.pop(ctx, value > 0 ? value : null), child: const Text('تأكيد')),
      ],
    ),
  );
}

/// Add or edit a bonus / deduction / absence / advance.
Future<void> showAdjustmentSheet(BuildContext context, Employee e, DateTime month, {SalaryAdjustment? existing}) {
  var type = existing?.type ?? AdjustmentType.deduction;
  var amount = existing?.amount ?? 0.0;
  var date = existing?.date ?? DateTime.now();
  final reason = TextEditingController(text: existing?.reason);
  final dayRate = e.salary / 30;

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${e.name} — ${Fmt.month(month)}',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final t in AdjustmentType.values)
                    ChoiceChip(
                      avatar: Icon(t.icon, size: 16, color: t.color),
                      label: Text(t.label),
                      selected: type == t,
                      onSelected: (_) => setState(() => type = t),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(switch (type) {
                AdjustmentType.advance => 'السلفة بتتسجل مصروف دلوقتي وبتتخصم من مرتب الشهر',
                AdjustmentType.absence => 'اليوم = ${Fmt.money(dayRate)} (المرتب ÷ ٣٠)',
                AdjustmentType.deduction => 'بيتخصم من مرتب الشهر',
                _ => 'بيتضاف على مرتب الشهر',
              }, style: Theme.of(ctx).textTheme.bodySmall),
              const SizedBox(height: 8),
              AmountField(label: 'المبلغ', value: amount, suffix: Fmt.symbol, onChanged: (v) => amount = v),
              if (type == AdjustmentType.absence && dayRate > 0)
                Wrap(
                  spacing: 6,
                  children: [
                    for (final days in [1, 2, 3, 0.5])
                      ActionChip(
                        label: Text(days == 0.5 ? 'نص يوم' : '${Fmt.number(days)} يوم'),
                        onPressed: () => setState(() => amount = (dayRate * days).roundToDouble()),
                      ),
                  ],
                ),
              const SizedBox(height: 8),
              TextField(
                controller: reason,
                decoration: const InputDecoration(labelText: 'السبب (اختياري)', hintText: 'مثال: تأخير / تارجت الشهر'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event),
                title: Text(Fmt.date(date)),
                onTap: () async {
                  final d = await pickDate(ctx, date);
                  if (d != null) setState(() => date = d);
                },
              ),
              FilledButton(
                onPressed: () {
                  if (amount <= 0) {
                    toast(ctx, 'اكتب المبلغ');
                    return;
                  }
                  final a = existing ?? SalaryAdjustment(employeeId: e.id, periodKey: Fmt.monthKey(month));
                  a
                    ..type = type
                    ..amount = amount
                    ..date = date
                    ..reason = reason.text.trim();
                  ctx.read<AppStore>().saveAdjustment(a);
                  Navigator.pop(ctx);
                },
                child: const Text('حفظ'),
              ),
              if (existing != null)
                TextButton(
                  onPressed: () {
                    ctx.read<AppStore>().deleteAdjustment(existing);
                    Navigator.pop(ctx);
                  },
                  child: const Text('حذف', style: TextStyle(color: Colors.red)),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class EmployeeFormScreen extends StatefulWidget {
  const EmployeeFormScreen({super.key, this.employee});
  final Employee? employee;

  @override
  State<EmployeeFormScreen> createState() => _EmployeeFormScreenState();
}

class _EmployeeFormScreenState extends State<EmployeeFormScreen> {
  late final Employee? _e = widget.employee;
  late final _name = TextEditingController(text: _e?.name);
  late final _job = TextEditingController(text: _e?.jobTitle);
  late final _phone = TextEditingController(text: _e?.phone);
  late final _notes = TextEditingController(text: _e?.notes);
  late double _salary = _e?.salary ?? 0;
  late int _payDay = _e?.payDay ?? 1;
  late DateTime? _hired = _e?.hireDate;
  late bool _active = _e?.isActive ?? true;
  late final List<CustomField> _fields = [
    for (final f in _e?.customFields ?? <CustomField>[]) CustomField(key: f.key, value: f.value),
  ];

  @override
  void dispose() {
    _name.dispose();
    _job.dispose();
    _phone.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      toast(context, 'اكتب اسم الموظف');
      return;
    }
    final store = context.read<AppStore>();
    final e = _e ?? Employee();
    e
      ..name = _name.text.trim()
      ..jobTitle = _job.text.trim()
      ..phone = _phone.text.trim()
      ..notes = _notes.text.trim()
      ..salary = _salary
      ..payDay = _payDay
      ..hireDate = _hired
      ..isActive = _active
      ..customFields = _fields.where((f) => f.key.trim().isNotEmpty).toList();
    store.upsert(store.employees, e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? 'موظف جديد' : 'تعديل الموظف'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم *', prefixIcon: Icon(Icons.person)),
          ),
          gap,
          TextField(
            controller: _job,
            decoration: const InputDecoration(
              labelText: 'الوظيفة',
              hintText: 'مثال: مصمم / مدير حسابات / مونتير',
              prefixIcon: Icon(Icons.work_outline),
            ),
          ),
          gap,
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'التليفون', prefixIcon: Icon(Icons.phone)),
          ),
          gap,
          AmountField(
            label: 'المرتب الشهري الأساسي',
            value: _salary,
            suffix: Fmt.symbol,
            onChanged: (v) => _salary = v,
          ),
          gap,
          DropdownButtonFormField<int>(
            initialValue: _payDay,
            decoration: const InputDecoration(labelText: 'يوم القبض', prefixIcon: Icon(Icons.event_repeat)),
            items: [
              for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('يوم ${Fmt.number(d)} من الشهر')),
            ],
            onChanged: (v) => setState(() => _payDay = v ?? 1),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_available),
            title: Text(_hired == null ? 'تاريخ التعيين (اختياري)' : 'اتعين ${Fmt.date(_hired!)}'),
            trailing: _hired == null
                ? null
                : IconButton(onPressed: () => setState(() => _hired = null), icon: const Icon(Icons.clear)),
            onTap: () async {
              final d = await pickDate(context, _hired ?? DateTime.now());
              if (d != null) setState(() => _hired = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('شغال حالياً'),
            subtitle: const Text('اقفلها لو ساب الشغل — بيفضل سجل مرتباته'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          const Divider(),
          Text('خانات إضافية', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('زي: الرقم القومي، رقم الحساب البنكي، التأمينات...', style: Theme.of(context).textTheme.bodySmall),
          for (var i = 0; i < _fields.length; i++)
            Padding(
              key: ObjectKey(_fields[i]),
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: _fields[i].key,
                      decoration: const InputDecoration(labelText: 'اسم الخانة'),
                      onChanged: (v) => _fields[i].key = v,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _fields[i].value,
                      decoration: const InputDecoration(labelText: 'القيمة'),
                      onChanged: (v) => _fields[i].value = v,
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() => _fields.removeAt(i)),
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                ],
              ),
            ),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: () => setState(() => _fields.add(CustomField())),
              icon: const Icon(Icons.add),
              label: const Text('إضافة خانة'),
            ),
          ),
          gap,
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_e != null)
            TextButton(
              onPressed: () async {
                if (await confirm(
                  context,
                  'حذف الموظف؟',
                  'المرتبات اللي اتصرفت هتفضل في المصروفات. لو ساب الشغل الأفضل تقفل "شغال حالياً" بدل الحذف.',
                )) {
                  if (!context.mounted) return;
                  context.read<AppStore>().deleteEmployee(_e);
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
