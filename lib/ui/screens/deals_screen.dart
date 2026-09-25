import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';

class DealsScreen extends StatefulWidget {
  const DealsScreen({super.key});

  @override
  State<DealsScreen> createState() => _DealsScreenState();
}

class _DealsScreenState extends State<DealsScreen> {
  DealStage? _stage;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final deals = store.deals.all..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final open = deals.where((d) => d.stage.isOpen).toList();
    final shown = _stage == null ? open : deals.where((d) => d.stage == _stage).toList();
    final won = deals.where((d) => d.stage == DealStage.won).length;
    final lost = deals.where((d) => d.stage == DealStage.lost).length;
    final winRate = won + lost == 0 ? 0.0 : won / (won + lost) * 100;
    final monthStart = startOfMonth(DateTime.now());
    final wonThisMonth = deals
        .where((d) => d.stage == DealStage.won && d.closedAt != null && !d.closedAt!.isBefore(monthStart))
        .fold<double>(0, (s, d) => s + d.value);

    return Scaffold(
      appBar: AppBar(title: const Text('الصفقات والفرص')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-deals',
        onPressed: () =>
            Navigator.push(context, MaterialPageRoute(builder: (_) => const DealFormScreen(), fullscreenDialog: true)),
        child: const Icon(Icons.add),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 90),
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: StatGrid(
              children: [
                StatCard(
                  title: 'قيمة الصفقات المفتوحة',
                  value: Fmt.compactMoney(open.fold<double>(0, (s, d) => s + d.value)),
                  icon: Icons.handshake,
                  color: Colors.purple,
                ),
                StatCard(
                  title: 'القيمة المتوقعة (مرجّحة)',
                  value: Fmt.compactMoney(open.fold<double>(0, (s, d) => s + d.weightedValue)),
                  icon: Icons.balance,
                  color: Colors.blue,
                ),
                StatCard(
                  title: 'مكسب هذا الشهر',
                  value: Fmt.compactMoney(wonThisMonth),
                  icon: Icons.emoji_events,
                  color: Colors.green,
                ),
                StatCard(title: 'نسبة النجاح', value: Fmt.percent(winRate), icon: Icons.percent, color: Colors.orange),
              ],
            ),
          ),
          ChipsBar<DealStage>(
            options: [null, ...DealStage.values],
            selected: _stage,
            label: (s) => s == null
                ? 'المفتوحة (${Fmt.number(open.length)})'
                : '${s.label} (${Fmt.number(deals.where((d) => d.stage == s).length)})',
            onSelected: (s) => setState(() => _stage = s),
          ),
          if (deals.isEmpty)
            const EmptyState(
              icon: Icons.handshake_outlined,
              title: 'لا توجد صفقات',
              message: 'تابع الفرص البيعية من أول تواصل حتى الإغلاق',
            ),
          for (final d in shown) DealTile(deal: d),
          if (shown.isNotEmpty)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'اضغط مطولاً على الصفقة لنقلها لمرحلة أخرى',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }
}

class DealTile extends StatelessWidget {
  const DealTile({super.key, required this.deal, this.showCustomer = true});
  final Deal deal;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final customer = showCustomer ? store.customer(deal.customerId) : null;
    final s = deal.stage;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: s.color.withValues(alpha: 0.15),
        child: Icon(s.icon, color: s.color),
      ),
      title: Text(deal.title, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(
        [
          if (customer != null) customer.name,
          if (s.isOpen && deal.expectedClose != null) 'الإغلاق ${Fmt.date(deal.expectedClose!)}' else s.label,
        ].join(' • '),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Fmt.money(deal.value), style: const TextStyle(fontWeight: FontWeight.bold)),
          if (s.isOpen) Text(Fmt.percent(deal.probability), style: const TextStyle(fontSize: 11)),
        ],
      ),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => DealFormScreen(deal: deal), fullscreenDialog: true),
      ),
      onLongPress: () async {
        final stage = await showModalBottomSheet<DealStage>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => ListView(
            shrinkWrap: true,
            children: [
              for (final st in DealStage.values.where((x) => x != s))
                ListTile(
                  leading: Icon(st.icon, color: st.color),
                  title: Text('نقل إلى: ${st.label}'),
                  onTap: () => Navigator.pop(ctx, st),
                ),
            ],
          ),
        );
        if (stage != null) {
          deal.moveTo(stage);
          store.upsert(store.deals, deal);
        }
      },
    );
  }
}

class DealFormScreen extends StatefulWidget {
  const DealFormScreen({super.key, this.deal, this.customerId});
  final Deal? deal;
  final String? customerId;

  @override
  State<DealFormScreen> createState() => _DealFormScreenState();
}

class _DealFormScreenState extends State<DealFormScreen> {
  late final Deal? _d = widget.deal;
  late final _title = TextEditingController(text: _d?.title);
  late final _notes = TextEditingController(text: _d?.notes);
  late double _value = _d?.value ?? 0;
  late DealStage _stage = _d?.stage ?? DealStage.newDeal;
  late double _probability = (_d?.probability ?? DealStage.newDeal.defaultProbability).toDouble();
  late String? _customerId = _d?.customerId ?? widget.customerId;
  late DateTime? _close = _d?.expectedClose;
  bool _createInvoice = false;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _save() {
    if (_title.text.trim().isEmpty) {
      toast(context, 'اكتب عنوان الصفقة');
      return;
    }
    final store = context.read<AppStore>();
    final d = _d ?? Deal();
    final stageChanged = d.stage != _stage;
    if (stageChanged) d.moveTo(_stage);
    d
      ..title = _title.text.trim()
      ..value = _value
      ..probability = _probability.round()
      ..customerId = _customerId
      ..expectedClose = _close
      ..notes = _notes.text.trim();
    store.upsert(store.deals, d);

    if (_createInvoice && _customerId != null) {
      final inv = Invoice(
        number: store.takeInvoiceNumber(),
        customerId: _customerId,
        dueDate: DateTime.now().add(Duration(days: store.business.defaultDueDays)),
        taxRate: store.business.defaultTaxRate,
        items: [InvoiceItem(name: d.title, quantity: 1, unitPrice: _value)],
      );
      store.upsert(store.invoices, inv);
      final c = store.customer(_customerId);
      if (c != null && c.status != CustomerStatus.vip) {
        c.status = CustomerStatus.active;
        store.upsert(store.customers, c);
      }
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    return Scaffold(
      appBar: AppBar(
        title: Text(_d == null ? 'صفقة جديدة' : 'تعديل الصفقة'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'عنوان الصفقة *'),
          ),
          gap,
          AmountField(label: 'القيمة', value: _value, suffix: Fmt.symbol, onChanged: (v) => _value = v),
          gap,
          CustomerDropdown(value: _customerId, onChanged: (v) => setState(() => _customerId = v)),
          gap,
          DropdownButtonFormField<DealStage>(
            initialValue: _stage,
            decoration: const InputDecoration(labelText: 'المرحلة'),
            items: [for (final s in DealStage.values) DropdownMenuItem(value: s, child: Text(s.label))],
            onChanged: (s) => setState(() {
              _stage = s ?? _stage;
              _probability = _stage.defaultProbability.toDouble();
            }),
          ),
          gap,
          Text('احتمال الإغلاق: ${Fmt.percent(_probability)}'),
          Slider(value: _probability, max: 100, divisions: 20, onChanged: (v) => setState(() => _probability = v)),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(_close == null ? 'تاريخ الإغلاق المتوقع' : 'الإغلاق المتوقع: ${Fmt.date(_close!)}'),
            trailing: _close == null
                ? null
                : IconButton(icon: const Icon(Icons.clear), onPressed: () => setState(() => _close = null)),
            onTap: () async {
              final d = await pickDate(context, _close ?? DateTime.now().add(const Duration(days: 30)));
              if (d != null) setState(() => _close = d);
            },
          ),
          if (_stage == DealStage.won && _d?.stage != DealStage.won && _customerId != null)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('إنشاء فاتورة بقيمة الصفقة'),
              value: _createInvoice,
              onChanged: (v) => setState(() => _createInvoice = v),
            ),
          gap,
          TextField(
            controller: _notes,
            maxLines: 4,
            decoration: const InputDecoration(labelText: 'ملاحظات'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_d != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف الصفقة؟', _d.title)) {
                  if (!context.mounted) return;
                  final store = context.read<AppStore>();
                  store.delete(store.deals, _d.id);
                  Navigator.pop(context);
                }
              },
              child: const Text('حذف الصفقة', style: TextStyle(color: Colors.red)),
            ),
        ],
      ),
    );
  }
}
