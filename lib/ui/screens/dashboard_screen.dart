import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/drive_sync.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'client_accounts_screen.dart';
import 'customers_screen.dart';
import 'deals_screen.dart';
import 'expenses_screen.dart';
import 'fixed_expenses_screen.dart';
import 'invoices_screen.dart';
import 'payroll_screen.dart';
import 'reports_screen.dart';
import 'sync_screen.dart';
import 'tasks_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, required this.onOpenTab});
  final ValueChanged<int> onOpenTab;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final sync = context.watch<DriveSync>();
    final now = DateTime.now();
    final monthStart = startOfMonth(now);
    final lastMonthStart = DateTime(now.year, now.month - 1);

    final payments = store.allPayments;
    final revenue = payments.where((p) => !p.$1.date.isBefore(monthStart)).fold<double>(0, (s, p) => s + p.$1.amount);
    final lastRevenue = payments
        .where((p) => !p.$1.date.isBefore(lastMonthStart) && p.$1.date.isBefore(monthStart))
        .fold<double>(0, (s, p) => s + p.$1.amount);
    final spent = store.expenses.all.where((e) => !e.date.isBefore(monthStart)).fold<double>(0, (s, e) => s + e.amount);
    final invoices = store.invoices.all;
    final outstanding = invoices.where((i) => i.status.isOutstanding).fold<double>(0, (s, i) => s + i.balance);
    final overdue = invoices.where((i) => i.status == InvoiceStatus.overdue).toList()
      ..sort((a, b) => a.dueDate.compareTo(b.dueDate));
    final customers = store.customers.all;
    final newCustomers = customers.where((c) => !c.createdAt.isBefore(monthStart)).length;
    final openDeals = store.deals.all.where((d) => d.stage.isOpen).toList();
    final focusTasks = store.tasks.all.where((t) => !t.isDone && (t.isOverdue || t.isDueToday)).toList()
      ..sort((a, b) => (a.dueDate ?? now).compareTo(b.dueDate ?? now));
    final lowStock = store.products.all.where((p) => p.isActive && p.isLowStock).toList();
    final target = store.business.monthlyTarget;

    String? growth;
    if (lastRevenue > 0) {
      final change = (revenue - lastRevenue) / lastRevenue * 100;
      growth = '${change >= 0 ? '▲' : '▼'} ${Fmt.percent(change.abs())} عن الشهر الماضي';
    }

    final clientAccounts = store.clientAccounts(from: monthStart);
    final subscribers = customers
        .where((c) => c.feeCycle == FeeCycle.monthly && c.fee > 0 && c.status != CustomerStatus.inactive)
        .toList();
    final unpaidSubs = store.unpaidSubscriptions(now);
    final endingContracts =
        customers
            .where((c) => c.contractEndingSoon || (c.contractExpired && c.status != CustomerStatus.inactive))
            .toList()
          ..sort((a, b) => a.contractEnd!.compareTo(b.contractEnd!));
    final toBill = store.subscribersToBill(now);

    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة التحكم'),
        actions: [
          if (sync.connected)
            IconButton(
              tooltip: 'مزامنة الآن',
              onPressed: sync.syncing ? null : () => sync.syncNow(interactive: true),
              icon: sync.syncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(sync.error == null ? Icons.cloud_done_outlined : Icons.cloud_off_outlined),
            ),
          IconButton(
            tooltip: 'التقارير',
            icon: const Icon(Icons.pie_chart_outline),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReportsScreen())),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            now.hour < 12 ? 'صباح الخير ☀️' : 'مساء الخير 🌙',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
          Text(
            store.business.name.isEmpty ? 'نشاطي التجاري' : store.business.name,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          Text(Fmt.weekday(now), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 14),
          if (!sync.connected) _SyncBanner(),
          _QuickActions(),
          const SizedBox(height: 14),
          StatGrid(
            children: [
              StatCard(
                title: 'إيرادات الشهر',
                value: Fmt.compactMoney(revenue),
                icon: Icons.south_west,
                color: Colors.green,
                subtitle: growth,
              ),
              StatCard(
                title: 'صافي ربح الشهر',
                value: Fmt.compactMoney(revenue - spent),
                icon: Icons.trending_up,
                color: revenue >= spent ? Colors.teal : Colors.red,
                subtitle: 'مصروفات ${Fmt.compactMoney(spent)}',
              ),
              StatCard(
                title: 'مستحقات لم تُحصّل',
                value: Fmt.compactMoney(outstanding),
                icon: Icons.hourglass_bottom,
                color: Colors.orange,
                subtitle: overdue.isEmpty ? null : '${Fmt.number(overdue.length)} فاتورة متأخرة',
              ),
              StatCard(
                title: 'العملاء',
                value: Fmt.number(customers.length),
                icon: Icons.people,
                color: Colors.blue,
                subtitle: newCustomers > 0 ? '+${Fmt.number(newCustomers)} هذا الشهر' : null,
              ),
              StatCard(
                title: 'صفقات مفتوحة',
                value: Fmt.compactMoney(openDeals.fold<double>(0, (s, d) => s + d.value)),
                icon: Icons.handshake,
                color: Colors.purple,
                subtitle: '${Fmt.number(openDeals.length)} صفقة',
              ),
              StatCard(
                title: 'مهام اليوم والمتأخرة',
                value: Fmt.number(focusTasks.length),
                icon: Icons.task_alt,
                color: Colors.pink,
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'حسابات العملاء — ${Fmt.month(now)}',
            icon: Icons.account_balance_wallet,
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ClientAccountsScreen())),
              child: const Text('الكل'),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (subscribers.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      '${Fmt.number(subscribers.length)} مشترك شهري • '
                      '${toBill.isNotEmpty ? '${Fmt.number(toBill.length)} فاتورة لم تصدر' : 'الفواتير صادرة'}'
                      '${unpaidSubs.isNotEmpty ? ' • ${Fmt.number(unpaidSubs.length)} لم يدفعوا' : ''}',
                      style: TextStyle(
                        color: unpaidSubs.isNotEmpty || toBill.isNotEmpty ? Colors.orange : Colors.green,
                      ),
                    ),
                  ),
                if (clientAccounts.isEmpty)
                  const Text('حدّد سعر كل عميل وسجّل اللي بتستلمه منه واللي بتصرفه عليه، وهتلاقي ربح كل عميل هنا.')
                else
                  for (final a in clientAccounts.take(5))
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: a.customer.name, color: a.customer.status.color, size: 38),
                      title: Text(a.customer.name),
                      subtitle: Text('استلمت ${Fmt.compactMoney(a.income)} • صرفت ${Fmt.compactMoney(a.spent)}'),
                      trailing: Text(
                        Fmt.compactMoney(a.profit),
                        style: TextStyle(fontWeight: FontWeight.bold, color: a.profit >= 0 ? Colors.teal : Colors.red),
                      ),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: a.customer.id)),
                      ),
                    ),
              ],
            ),
          ),
          if (store.employees.items.isNotEmpty ||
              store.fixedExpenses.items.isNotEmpty ||
              store.debts.items.isNotEmpty) ...[
            const SizedBox(height: 12),
            _CommitmentsCard(store: store, now: now, onOpen: () => onOpenTab(3)),
          ],
          if (target > 0) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'هدف الشهر',
              icon: Icons.flag,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LinearProgressIndicator(
                    value: (revenue / target).clamp(0, 1),
                    minHeight: 10,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${Fmt.money(revenue)} من ${Fmt.money(target)} (${Fmt.percent((revenue / target * 100).clamp(0, 999))})',
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'الإيرادات والمصروفات — آخر ٦ شهور',
            icon: Icons.bar_chart,
            child: _RevenueChart(store: store),
          ),
          if (endingContracts.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'عقود قربت تخلص',
              icon: Icons.event_busy,
              child: Column(
                children: [
                  for (final c in endingContracts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Avatar(name: c.name, color: c.status.color, size: 36),
                      title: Text(c.name),
                      subtitle: Text(
                        c.contractExpired ? 'انتهى ${Fmt.date(c.contractEnd!)}' : 'ينتهي ${Fmt.date(c.contractEnd!)}',
                      ),
                      trailing: Text(
                        Fmt.relative(c.contractEnd!),
                        style: TextStyle(
                          color: c.contractExpired ? Colors.red : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      onTap: () =>
                          Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: c.id))),
                    ),
                ],
              ),
            ),
          ],
          if (focusTasks.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'مهام تحتاج انتباهك',
              icon: Icons.notifications_active,
              trailing: TextButton(onPressed: () => onOpenTab(4), child: const Text('الكل')),
              child: Column(children: [for (final t in focusTasks.take(5)) TaskTile(task: t, dense: true)]),
            ),
          ],
          if (overdue.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'فواتير متأخرة السداد',
              icon: Icons.warning_amber_rounded,
              child: Column(children: [for (final i in overdue.take(5)) InvoiceTile(invoice: i)]),
            ),
          ],
          const SizedBox(height: 12),
          SectionCard(
            title: 'مسار المبيعات',
            icon: Icons.filter_alt,
            trailing: TextButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DealsScreen())),
              child: const Text('الصفقات'),
            ),
            child: _Pipeline(deals: openDeals),
          ),
          if (lowStock.isNotEmpty) ...[
            const SizedBox(height: 12),
            SectionCard(
              title: 'مخزون منخفض',
              icon: Icons.inventory_2,
              child: Column(
                children: [
                  for (final p in lowStock)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(p.name),
                      trailing: Pill('متبقي ${Fmt.number(p.stock)}', color: p.stock <= 0 ? Colors.red : Colors.orange),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

/// Salaries and fixed bills for this month: what's paid and what's coming.
class _CommitmentsCard extends StatelessWidget {
  const _CommitmentsCard({required this.store, required this.now, required this.onOpen});
  final AppStore store;
  final DateTime now;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final follow = store.followUp(now);
    final slips = store.payroll(now).where((p) => p.employee.isActive).toList();
    final salaryTotal = slips.fold(0.0, (s, p) => s + p.gross);
    final salaryLeft = slips.where((p) => !p.isPaid).fold(0.0, (s, p) => s + p.net);
    final key = Fmt.monthKey(now);
    final fixed = store.fixedExpenses.all.where((f) => f.isActive).toList();
    final fixedPaid = fixed.fold(0.0, (s, f) => s + (store.fixedPayment(f.id, key)?.amount ?? 0));
    final unpaid = store.unpaidFixed(now);
    final fixedLeft = unpaid.fold(0.0, (s, f) => s + f.amount);
    final due = unpaid.where((f) => f.dueDay <= now.day + 3).toList();
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    Widget row(String title, IconData icon, Color color, double total, double left, VoidCallback onTap) {
      final done = total <= 0 ? 1.0 : ((total - left) / total).clamp(0.0, 1.0);
      return InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 6),
                  Expanded(child: Text(title)),
                  Text(
                    left > 0 ? 'باقي ${Fmt.compactMoney(left)}' : 'اتدفع ✅',
                    style: TextStyle(fontWeight: FontWeight.bold, color: left > 0 ? Colors.orange : Colors.green),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              LinearProgressIndicator(value: done, minHeight: 6, color: color, borderRadius: BorderRadius.circular(6)),
              const SizedBox(height: 2),
              Text('من ${Fmt.money(total)}', style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }

    return SectionCard(
      title: 'التزامات ${Fmt.month(now)}',
      icon: Icons.event_repeat,
      trailing: Text(
        Fmt.compactMoney(salaryTotal + fixed.fold(0.0, (s, f) => s + f.amount)),
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (slips.isNotEmpty)
            row('المرتبات (${Fmt.number(slips.length)} موظف)', Icons.badge, Colors.indigo, salaryTotal, salaryLeft, () {
              open(const PayrollScreen());
            }),
          if (fixed.isNotEmpty)
            row('المصاريف الثابتة', Icons.home_work, Colors.brown, fixedPaid + fixedLeft, fixedLeft, () {
              open(const FixedExpensesScreen());
            }),
          for (final f in due.take(4))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(fixedIcon(f), color: f.dueDay < now.day ? Colors.red : Colors.orange),
              title: Text(f.title),
              subtitle: Text(
                f.dueDay < now.day
                    ? 'متأخر — كان يوم ${Fmt.number(f.dueDay)}'
                    : f.dueDay == now.day
                    ? 'النهارده'
                    : 'يوم ${Fmt.number(f.dueDay)}',
              ),
              trailing: Text(f.variable ? 'متغير' : Fmt.money(f.amount)),
              onTap: () => open(const FixedExpensesScreen()),
            ),
          if (follow.owedToMe.isNotEmpty || follow.iOwe.isNotEmpty) ...[
            const Divider(),
            Row(
              children: [
                Expanded(
                  child: _MiniTotal(
                    label: 'ليك عند الناس',
                    value: follow.owedToMe.fold(0.0, (s, d) => s + d.remaining),
                    color: Colors.green,
                  ),
                ),
                Expanded(
                  child: _MiniTotal(label: 'عليك للناس', value: follow.iOweTotal, color: Colors.red),
                ),
              ],
            ),
          ],
          Align(
            alignment: AlignmentDirectional.centerEnd,
            child: TextButton(onPressed: onOpen, child: const Text('المتابعة كاملة')),
          ),
        ],
      ),
    );
  }
}

class _MiniTotal extends StatelessWidget {
  const _MiniTotal({required this.label, required this.value, required this.color});
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text(
        Fmt.compactMoney(value),
        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: color),
      ),
      Text(label, style: Theme.of(context).textTheme.bodySmall),
    ],
  );
}

class _SyncBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      margin: const EdgeInsets.only(bottom: 14),
      child: ListTile(
        leading: const Icon(Icons.cloud_upload_outlined),
        title: const Text('احمِ بياناتك وزامنها بين أجهزتك'),
        subtitle: const Text('فعّل المزامنة مع Google Drive'),
        trailing: const Icon(Icons.chevron_left),
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SyncScreen())),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page, fullscreenDialog: true));

    Widget action(String label, IconData icon, Color color, VoidCallback onTap) => Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: color.withValues(alpha: 0.15),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12)),
            ],
          ),
        ),
      ),
    );

    return Row(
      children: [
        action('استلمت فلوس', Icons.south_west, Colors.green, () async {
          final c = await pickCustomer(context, title: 'استلمت فلوس من مين؟');
          if (c != null && context.mounted) showReceiveMoneySheet(context, c);
        }),
        action('صرفت', Icons.north_east, Colors.red, () async {
          final c = await pickCustomer(context, title: 'صرفت على مين؟');
          if (c != null && context.mounted) open(ExpenseFormScreen(customerId: c.id));
        }),
        action('عميل جديد', Icons.person_add_alt_1, Colors.blue, () => open(const CustomerFormScreen())),
        action('فاتورة', Icons.note_add, Colors.indigo, () => open(const InvoiceFormScreen())),
        action('تذكير', Icons.add_alarm, Colors.orange, () => open(const TaskFormScreen())),
      ],
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.store});
  final AppStore store;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final months = [for (var i = 5; i >= 0; i--) DateTime(now.year, now.month - i)];
    final payments = store.allPayments;
    final groups = <BarChartGroupData>[];
    var maxY = 0.0;
    for (var i = 0; i < months.length; i++) {
      final start = months[i];
      final end = DateTime(start.year, start.month + 1);
      bool inRange(DateTime d) => !d.isBefore(start) && d.isBefore(end);
      final rev = payments.where((p) => inRange(p.$1.date)).fold<double>(0, (s, p) => s + p.$1.amount);
      final exp = store.expenses.all.where((e) => inRange(e.date)).fold<double>(0, (s, e) => s + e.amount);
      maxY = [maxY, rev, exp].reduce((a, b) => a > b ? a : b);
      groups.add(
        BarChartGroupData(
          x: i,
          barsSpace: 3,
          barRods: [
            BarChartRodData(toY: rev, color: Colors.green, width: 10, borderRadius: BorderRadius.circular(3)),
            BarChartRodData(
              toY: exp,
              color: Colors.red.withValues(alpha: 0.7),
              width: 10,
              borderRadius: BorderRadius.circular(3),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        const Row(
          children: [_Legend('الإيرادات', Colors.green), SizedBox(width: 16), _Legend('المصروفات', Colors.redAccent)],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 200,
          child: BarChart(
            BarChartData(
              maxY: maxY == 0 ? 1 : maxY * 1.15,
              barGroups: groups,
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) => Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(Fmt.shortMonth(months[value.toInt()]), style: const TextStyle(fontSize: 11)),
                    ),
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                      BarTooltipItem(Fmt.compactMoney(rod.toY), const TextStyle(color: Colors.white, fontSize: 12)),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend(this.label, this.color);
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(fontSize: 12)),
    ],
  );
}

class _Pipeline extends StatelessWidget {
  const _Pipeline({required this.deals});
  final List<Deal> deals;

  @override
  Widget build(BuildContext context) {
    final totals = {
      for (final s in DealStage.openStages) s: deals.where((d) => d.stage == s).fold<double>(0, (a, d) => a + d.value),
    };
    final maxValue = totals.values.fold<double>(1, (a, b) => a > b ? a : b);
    return Column(
      children: [
        for (final s in DealStage.openStages)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(s.icon, size: 16, color: s.color),
                    const SizedBox(width: 4),
                    Text(s.label, style: TextStyle(color: s.color, fontSize: 13)),
                    const Spacer(),
                    Text(
                      '${Fmt.number(deals.where((d) => d.stage == s).length)} • ${Fmt.compactMoney(totals[s]!)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: totals[s]! / maxValue,
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
