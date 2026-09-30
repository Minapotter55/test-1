import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'payroll_screen.dart';

/// Common monthly bills offered as one-tap presets.
class FixedPreset {
  const FixedPreset(this.title, this.category, this.icon, {this.variable = false});
  final String title;
  final ExpenseCategory category;
  final IconData icon;
  final bool variable;
}

const fixedPresets = [
  FixedPreset('إيجار المكتب', ExpenseCategory.rent, Icons.home_work),
  FixedPreset('كهرباء', ExpenseCategory.utilities, Icons.bolt, variable: true),
  FixedPreset('مياه', ExpenseCategory.utilities, Icons.water_drop, variable: true),
  FixedPreset('غاز', ExpenseCategory.utilities, Icons.local_fire_department, variable: true),
  FixedPreset('إنترنت', ExpenseCategory.utilities, Icons.wifi),
  FixedPreset('تليفون وموبايلات', ExpenseCategory.utilities, Icons.phone_android),
  FixedPreset('اشتراكات برامج', ExpenseCategory.software, Icons.apps),
  FixedPreset('استضافة ودومين', ExpenseCategory.software, Icons.dns),
  FixedPreset('صيانة ونظافة', ExpenseCategory.maintenance, Icons.cleaning_services),
  FixedPreset('أمن وحراسة', ExpenseCategory.maintenance, Icons.security),
  FixedPreset('تأمينات اجتماعية', ExpenseCategory.taxes, Icons.health_and_safety),
  FixedPreset('ضرائب', ExpenseCategory.taxes, Icons.account_balance),
  FixedPreset('محاسب قانوني', ExpenseCategory.other, Icons.calculate),
  FixedPreset('قسط عربية / أجهزة', ExpenseCategory.other, Icons.credit_card),
  FixedPreset('مواصلات ثابتة', ExpenseCategory.transport, Icons.directions_car),
];

IconData fixedIcon(FixedExpense f) {
  for (final p in fixedPresets) {
    if (f.title.contains(p.title) || p.title.contains(f.title)) return p.icon;
  }
  return f.category.icon;
}

class FixedExpensesScreen extends StatefulWidget {
  const FixedExpensesScreen({super.key});

  @override
  State<FixedExpensesScreen> createState() => _FixedExpensesScreenState();
}

class _FixedExpensesScreenState extends State<FixedExpensesScreen> {
  DateTime _month = DateTime(DateTime.now().year, DateTime.now().month);

  void _openForm([FixedExpense? f]) => Navigator.push(
    context,
    MaterialPageRoute(builder: (_) => FixedExpenseFormScreen(fixed: f), fullscreenDialog: true),
  );

  Future<void> _pay(FixedExpense f) async {
    final amount = await askAmount(
      context,
      'دفع ${f.title} - ${Fmt.month(_month)}',
      initial: f.amount,
      hint: f.variable ? 'المبلغ بيتغير كل شهر — اكتب قيمة الفاتورة' : null,
    );
    if (amount == null || !mounted) return;
    context.read<AppStore>().payFixed(f, _month, amount: amount);
    toast(context, 'اتسجل ✅');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final list = store.sortedFixedExpenses;
    final key = Fmt.monthKey(_month);
    final active = list.where((f) => f.isActive).toList();
    final paidTotal = active.fold(0.0, (s, f) => s + (store.fixedPayment(f.id, key)?.amount ?? 0));
    final unpaid = active.where((f) => store.fixedPayment(f.id, key) == null).toList();
    final autoPayable = unpaid.where((f) => f.amount > 0 && !f.variable).toList();
    final now = DateTime.now();
    final isCurrent = _month.year == now.year && _month.month == now.month;

    return Scaffold(
      appBar: AppBar(title: const Text('المصاريف الثابتة')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-fixed',
        onPressed: _openForm,
        icon: const Icon(Icons.add),
        label: const Text('مصروف ثابت'),
      ),
      body: list.isEmpty
          ? ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const EmptyState(
                  icon: Icons.event_repeat,
                  title: 'ضيف مصاريفك الشهرية',
                  message: 'الإيجار والكهرباء والمياه والنت وأي حاجة بتدفعها كل شهر — والتطبيق يفكرك بميعادها',
                ),
                const Text('اختار بسرعة:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                _PresetChips(onPick: (p) => _openFormFromPreset(p)),
              ],
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: [
                MonthSwitcher(month: _month, onChanged: (m) => setState(() => _month = m)),
                StatGrid(
                  children: [
                    StatCard(
                      title: 'إجمالي الثابت شهرياً',
                      value: Fmt.money(store.monthlyFixedTotal),
                      icon: Icons.event_repeat,
                      color: Colors.indigo,
                      subtitle: '${Fmt.number(active.length)} بند',
                    ),
                    StatCard(
                      title: 'اتدفع الشهر ده',
                      value: Fmt.money(paidTotal),
                      icon: Icons.check_circle,
                      color: Colors.green,
                      subtitle: unpaid.isEmpty ? 'كله اتدفع ✅' : 'فاضل ${Fmt.number(unpaid.length)} بند',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                if (autoPayable.isNotEmpty)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final ok = await confirm(
                        context,
                        'تسجيل مصاريف ${Fmt.month(_month)}',
                        'هيتسجل ${Fmt.number(autoPayable.length)} بند بمبالغهم الثابتة '
                            '(${Fmt.money(autoPayable.fold(0.0, (s, f) => s + f.amount))}). '
                            'البنود المتغيرة زي الكهرباء سجّلها لوحدها.',
                        action: 'تسجيل',
                        destructive: false,
                      );
                      if (!ok || !context.mounted) return;
                      final n = context.read<AppStore>().payAllFixed(_month);
                      toast(context, 'اتسجل ${Fmt.number(n)} بند ✅');
                    },
                    icon: const Icon(Icons.playlist_add_check),
                    label: const Text('تسجيل كل الثابت (المبالغ الثابتة)'),
                  ),
                for (final f in list)
                  Builder(
                    builder: (context) {
                      final paid = store.fixedPayment(f.id, key);
                      final overdue = paid == null && f.isActive && isCurrent && now.day > f.dueDay;
                      final color = f.isActive ? f.category.color : Colors.grey;
                      return Card(
                        child: ListTile(
                          onTap: () => _openForm(f),
                          leading: CircleAvatar(
                            backgroundColor: color.withValues(alpha: 0.15),
                            child: Icon(fixedIcon(f), color: color),
                          ),
                          title: Text(f.title),
                          subtitle: Text(
                            [
                              f.categoryLabel,
                              'يوم ${Fmt.number(f.dueDay)}',
                              if (f.variable) 'مبلغ متغير',
                              if (!f.isActive) 'متوقف',
                            ].join(' • '),
                          ),
                          trailing: !f.isActive
                              ? Text(Fmt.money(f.amount))
                              : paid != null
                              ? Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.end,
                                  children: [
                                    Text(Fmt.money(paid.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                                    const Pill('اتدفع', color: Colors.green, icon: Icons.check),
                                  ],
                                )
                              : FilledButton.tonal(
                                  style: overdue
                                      ? FilledButton.styleFrom(
                                          backgroundColor: Colors.red.withValues(alpha: 0.15),
                                          foregroundColor: Colors.red,
                                        )
                                      : null,
                                  onPressed: () => _pay(f),
                                  child: Text(f.variable ? 'ادفع' : 'ادفع ${Fmt.compactMoney(f.amount)}'),
                                ),
                        ),
                      );
                    },
                  ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(4, 16, 4, 8),
                  child: Text('ضيف بند تاني:', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                _PresetChips(exclude: {for (final f in list) f.title}, onPick: (p) => _openFormFromPreset(p)),
              ],
            ),
    );
  }

  void _openFormFromPreset(FixedPreset p) => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => FixedExpenseFormScreen(
        fixed: FixedExpense(title: p.title, category: p.category, variable: p.variable),
        isNew: true,
      ),
      fullscreenDialog: true,
    ),
  );
}

class _PresetChips extends StatelessWidget {
  const _PresetChips({required this.onPick, this.exclude = const {}});
  final ValueChanged<FixedPreset> onPick;
  final Set<String> exclude;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final p in fixedPresets)
          if (!exclude.contains(p.title))
            ActionChip(avatar: Icon(p.icon, size: 16), label: Text(p.title), onPressed: () => onPick(p)),
      ],
    );
  }
}

class FixedExpenseFormScreen extends StatefulWidget {
  const FixedExpenseFormScreen({super.key, this.fixed, this.isNew = false});
  final FixedExpense? fixed;

  /// [fixed] is a pre-filled template that hasn't been saved yet.
  final bool isNew;

  @override
  State<FixedExpenseFormScreen> createState() => _FixedExpenseFormScreenState();
}

class _FixedExpenseFormScreenState extends State<FixedExpenseFormScreen> {
  late final FixedExpense? _f = widget.fixed;
  late final bool _existing = _f != null && !widget.isNew;
  late final _title = TextEditingController(text: _f?.title);
  late final _notes = TextEditingController(text: _f?.notes);
  late double _amount = _f?.amount ?? 0;
  late int _dueDay = _f?.dueDay ?? 1;
  late ExpenseCategory _category = _f?.category ?? ExpenseCategory.rent;
  late String _custom = _f?.customCategory ?? '';
  late bool _variable = _f?.variable ?? false;
  late bool _active = _f?.isActive ?? true;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب اسم المصروف');
      return;
    }
    if (_amount <= 0 && !_variable) {
      toast(context, 'اكتب المبلغ، أو علّم إنه مبلغ متغير');
      return;
    }
    final store = context.read<AppStore>();
    if (_custom.isNotEmpty && !store.business.expenseCategories.contains(_custom)) {
      store.updateBusiness((b) => b.expenseCategories.add(_custom));
    }
    final f = _f ?? FixedExpense();
    f
      ..title = _title.text.trim()
      ..amount = _amount
      ..dueDay = _dueDay
      ..category = _custom.isEmpty ? _category : ExpenseCategory.other
      ..customCategory = _custom
      ..variable = _variable
      ..isActive = _active
      ..notes = _notes.text.trim();
    store.upsert(store.fixedExpenses, f);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final store = context.watch<AppStore>();
    final history = _existing
        ? (store.expenses.all.where((e) => e.fixedExpenseId == _f!.id).toList()
            ..sort((a, b) => b.date.compareTo(a.date)))
        : <Expense>[];

    return Scaffold(
      appBar: AppBar(
        title: Text(_existing ? 'تعديل المصروف الثابت' : 'مصروف ثابت جديد'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'الاسم *', hintText: 'مثال: إيجار المكتب / فاتورة الكهرباء'),
          ),
          gap,
          AmountField(
            label: _variable ? 'المبلغ التقريبي' : 'المبلغ الشهري *',
            value: _amount,
            suffix: Fmt.symbol,
            onChanged: (v) => _amount = v,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('المبلغ بيتغير كل شهر'),
            subtitle: const Text('زي الكهرباء والمياه — هيسألك على المبلغ وقت الدفع'),
            value: _variable,
            onChanged: (v) => setState(() => _variable = v),
          ),
          DropdownButtonFormField<int>(
            initialValue: _dueDay,
            decoration: const InputDecoration(
              labelText: 'ميعاد الدفع',
              prefixIcon: Icon(Icons.event),
              helperText: 'هيجيلك تذكير قبلها بيوم ويوم الميعاد',
            ),
            items: [
              for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text('يوم ${Fmt.number(d)} من كل شهر')),
            ],
            onChanged: (v) => setState(() => _dueDay = v ?? 1),
          ),
          gap,
          Text('النوع', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in ExpenseCategory.values)
                if (c != ExpenseCategory.salaries)
                  ChoiceChip(
                    avatar: Icon(c.icon, size: 16),
                    label: Text(c.label),
                    selected: _custom.isEmpty && _category == c,
                    onSelected: (_) => setState(() {
                      _category = c;
                      _custom = '';
                    }),
                  ),
              for (final name in {...store.business.expenseCategories, if (_custom.isNotEmpty) _custom})
                ChoiceChip(
                  avatar: const Icon(Icons.label, size: 16),
                  label: Text(name),
                  selected: _custom == name,
                  onSelected: (_) => setState(() => _custom = name),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 16),
                label: const Text('نوع جديد'),
                onPressed: () async {
                  final name = await promptText(context, 'نوع مصروف جديد', hint: 'مثال: مصاريف بنكية');
                  if (name != null && name.isNotEmpty) setState(() => _custom = name);
                },
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('شغال'),
            subtitle: const Text('اقفله لو البند ده وقف (مثلاً لغيت الاشتراك)'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          TextField(
            controller: _notes,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'ملاحظات', hintText: 'رقم العداد / رقم الحساب / اسم المالك'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (history.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionCard(
              title: 'سجل الدفع',
              icon: Icons.history,
              trailing: Text(
                'متوسط ${Fmt.money(history.fold(0.0, (s, e) => s + e.amount) / history.length)}',
                style: const TextStyle(fontSize: 12),
              ),
              child: Column(
                children: [
                  for (final e in history.take(12))
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        e.periodKey == null ? Fmt.date(e.date) : Fmt.month(DateTime.parse('${e.periodKey}-01')),
                      ),
                      subtitle: Text('اتدفع ${Fmt.date(e.date)}'),
                      trailing: Text(Fmt.money(e.amount), style: const TextStyle(fontWeight: FontWeight.bold)),
                      onLongPress: () async {
                        if (await confirm(context, 'إلغاء الدفعة؟', e.title)) {
                          store.delete(store.expenses, e.id);
                        }
                      },
                    ),
                ],
              ),
            ),
          ],
          if (_existing)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف المصروف الثابت؟', 'المبالغ اللي اتدفعت قبل كده هتفضل في المصروفات')) {
                  if (!context.mounted) return;
                  store.delete(store.fixedExpenses, _f!.id);
                  Navigator.pop(context);
                }
              },
              child: const Text('حذف', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
