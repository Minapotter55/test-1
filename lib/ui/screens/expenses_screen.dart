import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  String? _category;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.expenses.all..sort((a, b) => b.date.compareTo(a.date));
    final list = _category == null ? all : all.where((e) => e.categoryLabel == _category).toList();
    final labels = {for (final e in all) e.categoryLabel}.toList()..sort();
    final months = <DateTime, List<Expense>>{};
    for (final e in list) {
      months.putIfAbsent(startOfMonth(e.date), () => []).add(e);
    }
    final keys = months.keys.toList()..sort((a, b) => b.compareTo(a));
    void open([Expense? e]) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ExpenseFormScreen(expense: e), fullscreenDialog: true),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المصروفات')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-expenses',
        onPressed: open,
        child: const Icon(Icons.add),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.account_balance_wallet_outlined,
              title: 'لا توجد مصروفات',
              message: 'سجّل مصروفاتك لتعرف صافي أرباحك الحقيقي',
              actionLabel: 'إضافة مصروف',
              onAction: open,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                ChipsBar<String>(
                  options: [null, ...labels],
                  selected: _category,
                  label: (c) => c ?? 'الكل',
                  onSelected: (c) => setState(() => _category = c),
                ),
                for (final m in keys) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Row(
                      children: [
                        Text(Fmt.month(m), style: const TextStyle(fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          Fmt.money(months[m]!.fold<double>(0, (s, e) => s + e.amount)),
                          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  for (final e in months[m]!)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: e.category.color.withValues(alpha: 0.15),
                        child: Icon(e.category.icon, color: e.category.color),
                      ),
                      title: Text(e.title),
                      subtitle: Text(
                        [
                          e.categoryLabel,
                          Fmt.date(e.date),
                          if (store.customer(e.customerId) != null) '👤 ${store.customer(e.customerId)!.name}',
                        ].join(' • '),
                      ),
                      trailing: Text(
                        Fmt.money(e.amount),
                        style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                      ),
                      onTap: () => open(e),
                    ),
                ],
              ],
            ),
    );
  }
}

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.expense, this.customerId});
  final Expense? expense;

  /// Pre-selects the client this money was spent on.
  final String? customerId;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  late final Expense? _e = widget.expense;
  late final _title = TextEditingController(text: _e?.title);
  late final _notes = TextEditingController(text: _e?.notes);
  late double _amount = _e?.amount ?? 0;
  late DateTime _date = _e?.date ?? DateTime.now();
  late ExpenseCategory _category = _e?.category ?? ExpenseCategory.other;
  late String _custom = _e?.customCategory ?? '';
  late String? _customerId = _e?.customerId ?? widget.customerId;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty || _amount <= 0) {
      toast(context, 'اكتب البيان والمبلغ');
      return;
    }
    final store = context.read<AppStore>();
    if (_custom.isNotEmpty && !store.business.expenseCategories.contains(_custom)) {
      store.updateBusiness((b) => b.expenseCategories.add(_custom));
    }
    final e = _e ?? Expense();
    e
      ..title = _title.text.trim()
      ..amount = _amount
      ..date = _date
      ..category = _custom.isEmpty ? _category : ExpenseCategory.other
      ..customCategory = _custom
      ..notes = _notes.text.trim()
      ..customerId = _customerId;
    store.upsert(store.expenses, e);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_e == null ? 'مصروف جديد' : 'تعديل المصروف'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'البيان *', hintText: 'مثال: إعلانات ممولة لمعمل الخبراء'),
          ),
          gap,
          AmountField(label: 'المبلغ *', value: _amount, suffix: Fmt.symbol, onChanged: (v) => _amount = v),
          gap,
          CustomerDropdown(
            label: 'صرفته على عميل؟ (اختياري)',
            value: _customerId,
            onChanged: (v) => setState(() => _customerId = v),
          ),
          gap,
          Text('نوع المصروف', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final c in ExpenseCategory.values)
                ChoiceChip(
                  avatar: Icon(c.icon, size: 16),
                  label: Text(c.label),
                  selected: _custom.isEmpty && _category == c,
                  onSelected: (_) => setState(() {
                    _category = c;
                    _custom = '';
                  }),
                ),
              for (final name in {
                ...context.read<AppStore>().business.expenseCategories,
                if (_custom.isNotEmpty) _custom,
              })
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
                  final name = await promptText(context, 'نوع مصروف جديد', hint: 'مثال: طباعة بروشورات');
                  if (name != null && name.isNotEmpty) setState(() => _custom = name);
                },
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
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_e != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف المصروف؟', _e.title)) {
                  if (!context.mounted) return;
                  final store = context.read<AppStore>();
                  store.delete(store.expenses, _e.id);
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
