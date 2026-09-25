import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/exporter.dart';
import '../../services/format.dart';
import '../widgets.dart';

enum _Period { thisMonth, lastMonth, last3Months, thisYear, all }

extension on _Period {
  String get label => switch (this) {
    _Period.thisMonth => 'هذا الشهر',
    _Period.lastMonth => 'الشهر الماضي',
    _Period.last3Months => 'آخر ٣ شهور',
    _Period.thisYear => 'هذا العام',
    _Period.all => 'الكل',
  };

  (DateTime, DateTime) get range {
    final now = DateTime.now();
    final month = startOfMonth(now);
    final end = now.add(const Duration(days: 1));
    return switch (this) {
      _Period.thisMonth => (month, end),
      _Period.lastMonth => (DateTime(now.year, now.month - 1), month),
      _Period.last3Months => (DateTime(now.year, now.month - 2), end),
      _Period.thisYear => (DateTime(now.year), end),
      _Period.all => (DateTime(1970), end),
    };
  }
}

class _Slice {
  _Slice(this.name, this.value, this.color);
  final String name;
  final double value;
  final Color color;
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  _Period _period = _Period.thisMonth;
  static const _palette = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.brown,
  ];

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final (start, end) = _period.range;
    bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);

    final payments = store.allPayments.where((p) => inRange(p.$1.date)).toList();
    final expenses = store.expenses.all.where((e) => inRange(e.date)).toList();
    final invoices = store.invoices.all.where((i) => i.state == InvoiceState.issued && inRange(i.issueDate)).toList();
    final revenue = payments.fold<double>(0, (s, p) => s + p.$1.amount);
    final spent = expenses.fold<double>(0, (s, e) => s + e.amount);
    final profit = revenue - spent;
    final sales = invoices.fold<double>(0, (s, i) => s + i.total);
    final newCustomers = store.customers.all.where((c) => inRange(c.createdAt)).toList();
    final closed = store.deals.all.where((d) => !d.stage.isOpen && d.closedAt != null && inRange(d.closedAt!)).toList();
    final winRate = closed.isEmpty ? 0.0 : closed.where((d) => d.stage == DealStage.won).length / closed.length * 100;

    final byCustomer = <String, double>{};
    for (final p in payments) {
      final name = store.customer(p.$2.customerId)?.name ?? 'بدون عميل';
      byCustomer[name] = (byCustomer[name] ?? 0) + p.$1.amount;
    }
    final topCustomers = (byCustomer.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).toList();

    final byItem = <String, double>{};
    for (final inv in invoices) {
      for (final item in inv.items) {
        byItem[item.name] = (byItem[item.name] ?? 0) + item.total;
      }
    }
    final topItems = (byItem.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(6).toList();

    final expenseSlices = [
      for (final c in ExpenseCategory.values)
        if (expenses.any((e) => e.category == c))
          _Slice(c.label, expenses.where((e) => e.category == c).fold<double>(0, (s, e) => s + e.amount), c.color),
    ]..sort((a, b) => b.value.compareTo(a.value));

    final sources = <String, int>{};
    for (final c in newCustomers) {
      final s = c.source.isEmpty ? 'غير محدد' : c.source;
      sources[s] = (sources[s] ?? 0) + 1;
    }
    final sourceEntries = sources.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final sourceSlices = [
      for (var i = 0; i < sourceEntries.length; i++)
        _Slice(sourceEntries[i].key, sourceEntries[i].value.toDouble(), _palette[i % _palette.length]),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('التقارير'),
        actions: [
          if (_period == _Period.thisMonth || _period == _Period.lastMonth)
            IconButton(
              tooltip: 'تصدير Excel',
              icon: const Icon(Icons.table_view),
              onPressed: () async {
                final file = await context.read<Exporter>().exportMonth(start);
                if (context.mounted) await shareFile(context, file);
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<_Period>(
            initialValue: _period,
            decoration: const InputDecoration(labelText: 'الفترة', prefixIcon: Icon(Icons.date_range)),
            items: [for (final p in _Period.values) DropdownMenuItem(value: p, child: Text(p.label))],
            onChanged: (p) => setState(() => _period = p ?? _period),
          ),
          const SizedBox(height: 12),
          StatGrid(
            children: [
              StatCard(title: 'المحصّل', value: Fmt.compactMoney(revenue), icon: Icons.south_west, color: Colors.green),
              StatCard(title: 'المصروفات', value: Fmt.compactMoney(spent), icon: Icons.north_east, color: Colors.red),
              StatCard(
                title: 'صافي الربح',
                value: Fmt.compactMoney(profit),
                icon: Icons.trending_up,
                color: profit >= 0 ? Colors.teal : Colors.red,
                subtitle: revenue > 0 ? 'هامش ${Fmt.percent(profit / revenue * 100)}' : null,
              ),
              StatCard(
                title: 'المبيعات (فواتير)',
                value: Fmt.compactMoney(sales),
                icon: Icons.receipt_long,
                color: Colors.blue,
                subtitle: '${Fmt.number(invoices.length)} فاتورة',
              ),
              StatCard(
                title: 'متوسط الفاتورة',
                value: Fmt.compactMoney(invoices.isEmpty ? 0 : sales / invoices.length),
                icon: Icons.functions,
                color: Colors.orange,
              ),
              StatCard(
                title: 'عملاء جدد',
                value: Fmt.number(newCustomers.length),
                icon: Icons.person_add,
                color: Colors.purple,
                subtitle: closed.isEmpty ? null : 'نجاح الصفقات ${Fmt.percent(winRate)}',
              ),
            ],
          ),
          if (topCustomers.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'أعلى العملاء تحصيلاً',
              icon: Icons.star,
              child: _Bars(
                slices: [for (final e in topCustomers) _Slice(e.key, e.value, Theme.of(context).colorScheme.primary)],
              ),
            ),
          ],
          if (topItems.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'أكثر المنتجات والخدمات مبيعاً',
              icon: Icons.inventory_2,
              child: _Bars(slices: [for (final e in topItems) _Slice(e.key, e.value, Colors.purple)]),
            ),
          ],
          if (expenseSlices.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'توزيع المصروفات',
              icon: Icons.pie_chart,
              child: _Pie(slices: expenseSlices),
            ),
          ],
          if (sourceSlices.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'مصادر العملاء الجدد',
              icon: Icons.call_received,
              child: _Pie(slices: sourceSlices, money: false),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _Bars extends StatelessWidget {
  const _Bars({required this.slices});
  final List<_Slice> slices;

  @override
  Widget build(BuildContext context) {
    final max = slices.fold<double>(1, (m, s) => s.value > m ? s.value : m);
    return Column(
      children: [
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s.name, overflow: TextOverflow.ellipsis)),
                    Text(Fmt.compactMoney(s.value), style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 3),
                LinearProgressIndicator(
                  value: s.value / max,
                  color: s.color,
                  minHeight: 8,
                  borderRadius: BorderRadius.circular(8),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Pie extends StatelessWidget {
  const _Pie({required this.slices, this.money = true});
  final List<_Slice> slices;
  final bool money;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (s, x) => s + x.value);
    return Row(
      children: [
        SizedBox(
          width: 130,
          height: 130,
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 32,
              sections: [
                for (final s in slices)
                  PieChartSectionData(value: s.value, color: s.color, radius: 30, showTitle: false),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (final s in slices)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      CircleAvatar(radius: 5, backgroundColor: s.color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(s.name, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
                      ),
                      Text(
                        money ? Fmt.percent(total > 0 ? s.value / total * 100 : 0) : Fmt.number(s.value),
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
