import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/contact_actions.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'client_accounts_screen.dart';
import 'expenses_screen.dart';
import 'invoices_screen.dart';
import 'payroll_screen.dart';
import 'products_screen.dart';
import 'reports_screen.dart';

enum _Period {
  today('اليوم'),
  week('آخر ٧ أيام'),
  month('الشهر ده'),
  all('الكل');

  const _Period(this.label);
  final String label;

  DateTime? get from {
    final now = DateTime.now();
    return switch (this) {
      _Period.today => DateTime(now.year, now.month, now.day),
      _Period.week => DateTime(now.year, now.month, now.day - 6),
      _Period.month => DateTime(now.year, now.month),
      _Period.all => null,
    };
  }
}

/// Opens a new sale and shows a snackbar with a link to the receipt.
Future<void> openNewSale(BuildContext context, {Customer? customer, SaleType type = SaleType.cash}) async {
  final inv = await Navigator.push<Invoice>(
    context,
    MaterialPageRoute(
      builder: (_) => NewSaleScreen(customer: customer, type: type),
      fullscreenDialog: true,
    ),
  );
  if (inv == null || !context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('اتسجل ${inv.saleType!.label} — ${Fmt.money(inv.total)} ✅'),
        action: SnackBarAction(
          label: 'الفاتورة',
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: inv.id))),
        ),
      ),
    );
}

/// Shop sales split into cash and credit, with discounts and profit.
class SalesScreen extends StatefulWidget {
  const SalesScreen({super.key});

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  _Period _period = _Period.today;
  SaleType _tab = SaleType.cash;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final from = _period.from;
    final sum = store.salesSummary(from: from);
    final list = store.sales(from: from, type: _tab);
    final spent = store.expenses.all
        .where((e) => from == null || !e.date.isBefore(from))
        .fold(0.0, (s, e) => s + e.amount);
    void push(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(
        title: const Text('المبيعات'),
        actions: [
          IconButton(
            tooltip: 'حسابات الآجل',
            onPressed: () => push(const CreditAccountsScreen()),
            icon: const Icon(Icons.menu_book),
          ),
          IconButton(
            tooltip: 'التقارير والطباعة',
            onPressed: () => push(const ReportsScreen()),
            icon: const Icon(Icons.print),
          ),
          IconButton(
            tooltip: 'رصيد المحل',
            onPressed: () => push(const ProductsScreen()),
            icon: const Icon(Icons.warehouse),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-sales',
        onPressed: () => openNewSale(context, type: _tab),
        icon: const Icon(Icons.point_of_sale),
        label: const Text('بيع جديد'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          ChipsBar<_Period>(
            options: _Period.values,
            selected: _period,
            label: (p) => p!.label,
            onSelected: (p) => setState(() => _period = p ?? _Period.today),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: StatGrid(
              children: [
                StatCard(
                  title: SaleType.cash.label,
                  value: Fmt.money(sum.cashTotal),
                  icon: SaleType.cash.icon,
                  color: SaleType.cash.color,
                ),
                StatCard(
                  title: SaleType.credit.label,
                  value: Fmt.money(sum.creditTotal),
                  icon: SaleType.credit.icon,
                  color: SaleType.credit.color,
                  subtitle: sum.creditCollected > 0 ? 'اتحصّل من الآجل ${Fmt.money(sum.creditCollected)}' : null,
                ),
                StatCard(
                  title: 'ربح البيع (بعد التكلفة)',
                  value: Fmt.money(sum.profit),
                  icon: Icons.trending_up,
                  color: sum.profit >= 0 ? Colors.teal : Colors.red,
                  subtitle: 'تكلفة البضاعة ${Fmt.money(sum.cost)}',
                ),
                StatCard(
                  title: 'الخصومات',
                  value: Fmt.money(sum.discounts),
                  icon: Icons.local_offer,
                  color: Colors.pink,
                  subtitle: '${Fmt.number(sum.count)} عملية بيع',
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  children: [
                    MoneyRow('ربح البيع', sum.profit, color: Colors.teal),
                    MoneyRow('المصروفات', spent, color: Colors.red, sign: '- '),
                    const Divider(),
                    MoneyRow('صافي الربح', sum.profit - spent, bold: true),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
            child: SegmentedButton<SaleType>(
              segments: [
                for (final t in SaleType.values)
                  ButtonSegment(
                    value: t,
                    icon: Icon(t.icon),
                    label: Text('${t.label} (${Fmt.number(store.sales(from: from, type: t).length)})'),
                  ),
              ],
              selected: {_tab},
              onSelectionChanged: (s) => setState(() => _tab = s.first),
            ),
          ),
          if (list.isEmpty)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'مفيش ${_tab.label} في الفترة دي',
                textAlign: TextAlign.center,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          for (final inv in list) SaleTile(invoice: inv),
        ],
      ),
    );
  }
}

class SaleTile extends StatelessWidget {
  const SaleTile({super.key, required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    final inv = invoice;
    final store = context.read<AppStore>();
    final customer = store.customer(inv.customerId);
    final type = inv.saleType ?? SaleType.cash;
    final itemsText = inv.items.map((i) => i.quantity == 1 ? i.name : '${Fmt.number(i.quantity)}× ${i.name}');
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: type.color.withValues(alpha: 0.15),
        child: Icon(type.icon, color: type.color),
      ),
      title: Text(itemsText.join('، '), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          Fmt.dateTime(inv.issueDate),
          if (customer != null) customer.name,
          if (inv.discount > 0) 'خصم ${Fmt.money(inv.discount)}',
        ].join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Fmt.money(inv.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          if (type == SaleType.credit && inv.balance > 0.009)
            Pill('باقي ${Fmt.money(inv.balance)}', color: Colors.orange)
          else if (type == SaleType.credit)
            const Pill('اتسدد', color: Colors.green, icon: Icons.check),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: inv.id))),
    );
  }
}

class _CartLine {
  _CartLine(this.name, this.price, this.cost, {this.productId});
  final String name;
  double price;
  final double cost;
  final String? productId;
  double qty = 1;
  double get total => qty * price;
}

/// Point of sale: pick items, discount, cash or credit.
class NewSaleScreen extends StatefulWidget {
  const NewSaleScreen({super.key, this.customer, this.type = SaleType.cash});
  final Customer? customer;
  final SaleType type;

  @override
  State<NewSaleScreen> createState() => _NewSaleScreenState();
}

class _NewSaleScreenState extends State<NewSaleScreen> {
  late SaleType _type = widget.type;
  late Customer? _customer = widget.customer;
  final _lines = <_CartLine>[];

  /// What the user typed in the discount box: pounds, or a percentage when [_percent].
  double _discountInput = 0;
  bool _percent = false;
  double _paidNow = 0;
  String _q = '';

  double get _subtotal => _lines.fold(0.0, (s, l) => s + l.total);
  double get _discount =>
      _percent ? (_subtotal * _discountInput.clamp(0, 100) / 100 * 100).roundToDouble() / 100 : _discountInput;
  double get _total => (_subtotal - _discount).clamp(0, double.infinity).toDouble();
  double get _cost => _lines.fold(0.0, (s, l) => s + l.qty * l.cost);

  void _add(Product p) {
    final existing = _lines.where((l) => l.productId == p.id).firstOrNull;
    final inCart = existing?.qty ?? 0;
    if (p.trackStock && p.stock - inCart <= 0) {
      toast(context, 'تنبيه: ${p.name} خلص من المخزون');
    }
    setState(() {
      if (existing != null) {
        existing.qty += 1;
      } else {
        _lines.add(_CartLine(p.name, p.price, p.cost, productId: p.id));
      }
    });
  }

  Future<void> _addFreeItem() async {
    final name = await promptText(context, 'صنف حر', hint: 'اسم الصنف');
    if (name == null || name.isEmpty || !mounted) return;
    final price = await askAmount(context, 'سعر $name');
    if (price == null || !mounted) return;
    setState(() => _lines.add(_CartLine(name, price, 0)));
  }

  Future<void> _pickCustomer() async {
    final c = await pickCustomer(context, title: 'البيع الآجل لمين؟');
    if (c != null) setState(() => _customer = c);
  }

  Future<void> _newCustomer() async {
    final name = await promptText(context, 'عميل جديد', hint: 'اسم العميل');
    if (name == null || name.isEmpty || !mounted) return;
    final store = context.read<AppStore>();
    final c = Customer(name: name, status: CustomerStatus.active);
    store.upsert(store.customers, c);
    setState(() => _customer = c);
  }

  void _finish() {
    if (_lines.isEmpty) {
      toast(context, 'ضيف صنف الأول');
      return;
    }
    if (_type == SaleType.credit && _customer == null) {
      toast(context, 'البيع الآجل لازم يكون على عميل — اختار العميل');
      return;
    }
    if (_discount > _subtotal) {
      toast(context, 'الخصم أكبر من الإجمالي');
      return;
    }
    final inv = context.read<AppStore>().recordSale(
      items: [
        for (final l in _lines)
          InvoiceItem(name: l.name, quantity: l.qty, unitPrice: l.price, productId: l.productId, unitCost: l.cost),
      ],
      type: _type,
      discount: _discount,
      customer: _customer,
      paidNow: _paidNow,
    );
    Navigator.pop(context, inv);
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final theme = Theme.of(context);
    final products =
        store.products.all
            .where((p) => p.isActive)
            .where((p) => _q.isEmpty || p.name.contains(_q) || p.sku.contains(_q) || p.category.contains(_q))
            .toList()
          ..sort((a, b) {
            if (a.isService != b.isService) return a.isService ? 1 : -1;
            return a.name.compareTo(b.name);
          });
    final owed = _customer == null ? 0.0 : store.balanceOf(_customer!.id);

    return Scaffold(
      appBar: AppBar(title: const Text('بيع جديد')),
      bottomNavigationBar: SafeArea(
        child: Material(
          elevation: 8,
          color: theme.colorScheme.surfaceContainer,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('الصافي', style: theme.textTheme.bodySmall),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          Fmt.money(_total),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: _type.color, minimumSize: const Size(0, 48)),
                  onPressed: _finish,
                  icon: Icon(_type.icon),
                  label: Text(_type == SaleType.cash ? 'تم البيع كاش' : 'سجّل على الحساب'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
        children: [
          SegmentedButton<SaleType>(
            segments: [
              for (final t in SaleType.values) ButtonSegment(value: t, icon: Icon(t.icon), label: Text(t.label)),
            ],
            selected: {_type},
            onSelectionChanged: (s) => setState(() => _type = s.first),
          ),
          const SizedBox(height: 8),
          Card(
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: _customer == null
                  ? const CircleAvatar(child: Icon(Icons.person_outline))
                  : Avatar(name: _customer!.name, size: 40),
              title: Text(
                _customer?.name ?? (_type == SaleType.credit ? 'اختار العميل *' : 'عميل (اختياري)'),
                style: TextStyle(color: _customer == null && _type == SaleType.credit ? Colors.red : null),
              ),
              subtitle: owed > 0 ? Text('عليه حالياً ${Fmt.money(owed)}') : null,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(tooltip: 'عميل جديد', onPressed: _newCustomer, icon: const Icon(Icons.person_add_alt)),
                  if (_customer != null)
                    IconButton(
                      tooltip: 'شيل العميل',
                      onPressed: () => setState(() => _customer = null),
                      icon: const Icon(Icons.clear),
                    ),
                ],
              ),
              onTap: _pickCustomer,
            ),
          ),
          const SizedBox(height: 10),

          // Cart
          if (_lines.isNotEmpty)
            SectionCard(
              title: 'الفاتورة (${Fmt.number(_lines.length)} صنف)',
              icon: Icons.shopping_cart,
              child: Column(
                children: [
                  for (final l in _lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () async {
                                final p = await askAmount(context, 'سعر ${l.name}', initial: l.price);
                                if (p != null) setState(() => l.price = p);
                              },
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                  Text('${Fmt.money(l.price)} للقطعة', style: theme.textTheme.bodySmall),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() {
                              if (l.qty > 1) {
                                l.qty -= 1;
                              } else {
                                _lines.remove(l);
                              }
                            }),
                            icon: Icon(l.qty > 1 ? Icons.remove_circle_outline : Icons.delete_outline),
                          ),
                          Text(Fmt.number(l.qty), style: const TextStyle(fontWeight: FontWeight.bold)),
                          IconButton(
                            visualDensity: VisualDensity.compact,
                            onPressed: () => setState(() => l.qty += 1),
                            icon: const Icon(Icons.add_circle_outline),
                          ),
                          SizedBox(
                            width: 84,
                            child: Text(
                              Fmt.money(l.total),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const Divider(),
                  MoneyRow('الإجمالي', _subtotal),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: AmountField(
                          label: _percent ? 'نسبة الخصم' : 'قيمة الخصم',
                          value: _discountInput,
                          suffix: _percent ? '٪' : Fmt.symbol,
                          onChanged: (v) => setState(() => _discountInput = v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        segments: [
                          ButtonSegment(value: false, label: Text(Fmt.symbol)),
                          const ButtonSegment(value: true, label: Text('٪')),
                        ],
                        selected: {_percent},
                        onSelectionChanged: (v) => setState(() {
                          _percent = v.first;
                          _discountInput = 0;
                        }),
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      spacing: 6,
                      children: [
                        for (final pct in const [5, 10, 15, 20])
                          ActionChip(
                            label: Text('${Fmt.number(pct)}٪'),
                            onPressed: () => setState(() {
                              _percent = true;
                              _discountInput = pct.toDouble();
                            }),
                          ),
                        if (_discount > 0)
                          ActionChip(
                            label: const Text('بدون خصم'),
                            onPressed: () => setState(() => _discountInput = 0),
                          ),
                      ],
                    ),
                  ),
                  if (_discount > 0)
                    MoneyRow(
                      _percent ? 'الخصم (${Fmt.number(_discountInput)}٪)' : 'الخصم',
                      _discount,
                      color: Colors.pink,
                      sign: '- ',
                    ),
                  MoneyRow('الصافي', _total, bold: true),
                  if (_cost > 0)
                    MoneyRow('ربحك من البيعة دي', _total - _cost, color: _total >= _cost ? Colors.teal : Colors.red),
                  if (_type == SaleType.credit) ...[
                    const SizedBox(height: 8),
                    AmountField(
                      label: 'دفع مقدم دلوقتي (اختياري)',
                      value: _paidNow,
                      suffix: Fmt.symbol,
                      onChanged: (v) => setState(() => _paidNow = v),
                    ),
                    MoneyRow(
                      'هيتسجل عليه',
                      (_total - _paidNow).clamp(0, double.infinity).toDouble(),
                      bold: true,
                      color: Colors.orange,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 10),

          // Products
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'دوّر على صنف بالاسم أو الكود',
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _q = v.trim()),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(onPressed: _addFreeItem, icon: const Icon(Icons.add), label: const Text('صنف حر')),
            ],
          ),
          const SizedBox(height: 6),
          if (store.products.items.isEmpty)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const Text('لسه ما ضفتش منتجات. ضيف منتجاتك بسعر الشراء وسعر البيع عشان تبيع بسرعة.'),
                  TextButton.icon(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const ProductFormScreen(), fullscreenDialog: true),
                    ),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة منتج'),
                  ),
                ],
              ),
            ),
          for (final p in products)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                dense: true,
                onTap: () => _add(p),
                leading: Icon(
                  p.isService ? Icons.design_services : Icons.inventory_2,
                  color: p.trackStock && p.stock <= 0 ? Colors.red : null,
                ),
                title: Text(p.name),
                subtitle: Text(
                  [
                    if (p.trackStock) p.stock <= 0 ? 'خلص من المخزون' : 'متاح ${Fmt.number(p.stock)}',
                    if (p.category.isNotEmpty) p.category,
                  ].join(' • '),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(Fmt.money(p.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                    const SizedBox(width: 6),
                    Icon(Icons.add_shopping_cart, color: theme.colorScheme.primary),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Customers buying on credit: who owes what.
class CreditAccountsScreen extends StatefulWidget {
  const CreditAccountsScreen({super.key});

  @override
  State<CreditAccountsScreen> createState() => _CreditAccountsScreenState();
}

class _CreditAccountsScreenState extends State<CreditAccountsScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.creditAccounts();
    final list = all.where((a) => _q.isEmpty || a.$1.name.contains(_q) || a.$1.phone.contains(_q)).toList();
    final total = all.fold(0.0, (s, a) => s + a.$2);
    final monthStart = DateTime(DateTime.now().year, DateTime.now().month);
    final sum = store.salesSummary(from: monthStart);

    return Scaffold(
      appBar: AppBar(title: const Text('حسابات الآجل')),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'fab-credit',
        onPressed: () => openNewSale(context, type: SaleType.credit),
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('بيع آجل'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
        children: [
          StatGrid(
            children: [
              StatCard(
                title: 'إجمالي الآجل عند الناس',
                value: Fmt.money(total),
                icon: Icons.menu_book,
                color: Colors.orange,
                subtitle: '${Fmt.number(all.length)} عميل',
              ),
              StatCard(
                title: 'اتحصّل من الآجل الشهر ده',
                value: Fmt.money(sum.creditCollected),
                icon: Icons.south_west,
                color: Colors.green,
                subtitle: 'اتباع آجل ${Fmt.money(sum.creditTotal)}',
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'دوّر بالاسم أو التليفون'),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
          const SizedBox(height: 6),
          if (all.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('مفيش حد عليه آجل دلوقتي 👌', textAlign: TextAlign.center),
            ),
          for (final (c, owed) in list)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 3),
              child: ListTile(
                leading: Avatar(name: c.name, size: 40),
                title: Text(c.name),
                subtitle: Text(_lastMove(store, c)),
                trailing: Text(
                  Fmt.money(owed),
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange),
                ),
                onTap: () =>
                    Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerLedgerScreen(customerId: c.id))),
              ),
            ),
        ],
      ),
    );
  }

  String _lastMove(AppStore store, Customer c) {
    final s = store.statementOf(c.id);
    if (s.isEmpty) return '';
    final last = s.last;
    return 'آخر حركة: ${last.credit > 0 ? 'دفع' : 'سحب'} ${Fmt.relative(last.date)}';
  }
}

/// A customer's account statement: purchases on credit, payments and the running balance.
class CustomerLedgerScreen extends StatelessWidget {
  const CustomerLedgerScreen({super.key, required this.customerId});
  final String customerId;

  Future<void> _pay(BuildContext context, Customer c, double owed) async {
    final amount = await askAmount(
      context,
      'دفعة من ${c.name}',
      initial: owed,
      hint: 'عليه ${Fmt.money(owed)} — اكتب المبلغ اللي دفعه (ممكن جزء)',
    );
    if (amount == null || !context.mounted) return;
    final store = context.read<AppStore>();
    final pay = amount > owed ? owed : amount;
    store.payOnAccount(c, pay);
    if (amount > owed + 0.009) {
      // Paid more than owed: keep the extra as money received in advance.
      store.receiveMoney(c, amount - owed, note: 'زيادة على الحساب (مقدم)');
    }
    toast(context, 'اتسجلت دفعة ${Fmt.money(amount)} ✅');
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final c = store.customer(customerId);
    if (c == null) return const Scaffold(body: Center(child: Text('العميل اتحذف')));
    final owed = store.balanceOf(c.id);
    final entries = store.statementOf(c.id).reversed.toList();
    final took = entries.fold(0.0, (s, e) => s + e.debit);
    final paid = entries.fold(0.0, (s, e) => s + e.credit);

    return Scaffold(
      appBar: AppBar(
        title: Text(c.name),
        actions: [
          if (c.phone.isNotEmpty || c.whatsapp.isNotEmpty)
            IconButton(
              tooltip: 'تذكير على واتساب',
              onPressed: () => ContactActions.open(
                ContactActions.whatsapp(
                  c.whatsapp.isNotEmpty ? c.whatsapp : c.phone,
                  store.business.countryCode,
                  text:
                      'أهلاً ${c.name}، حسابك عندنا ${Fmt.money(owed)}.${store.business.name.isEmpty ? '' : ' — ${store.business.name}'}',
                ),
              ),
              icon: const Icon(Icons.chat),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(owed > 0.009 ? 'عليه' : 'الحساب مسدد ✅'),
                  Text(
                    Fmt.money(owed),
                    style: Theme.of(context).textTheme.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: owed > 0.009 ? Colors.orange : Colors.green),
                  ),
                  const SizedBox(height: 8),
                  MoneyRow('إجمالي المسحوبات', took),
                  MoneyRow('إجمالي اللي دفعه', paid, color: Colors.green),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: owed > 0.009 ? () => _pay(context, c, owed) : null,
                  icon: const Icon(Icons.payments),
                  label: const Text('دفع جزء / الكل'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => openNewSale(context, customer: c, type: SaleType.credit),
                  icon: const Icon(Icons.add_shopping_cart),
                  label: const Text('سحب جديد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SectionCard(
            title: 'كشف الحساب',
            icon: Icons.receipt_long,
            child: entries.isEmpty
                ? const Text('لسه مفيش حركات')
                : Column(
                    children: [
                      for (final e in entries)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(
                            e.credit > 0 ? Icons.south_west : Icons.shopping_bag_outlined,
                            color: e.credit > 0 ? Colors.green : Colors.orange,
                          ),
                          title: Text(e.title),
                          subtitle: Text('${Fmt.date(e.date)} • الرصيد بعدها ${Fmt.money(e.balance)}'),
                          trailing: Text(
                            e.credit > 0 ? '- ${Fmt.money(e.credit)}' : '+ ${Fmt.money(e.debit)}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: e.credit > 0 ? Colors.green : Colors.orange,
                            ),
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: e.invoice.id)),
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

/// Quick shortcuts to record common running costs.
class OperatingExpenseChips extends StatelessWidget {
  const OperatingExpenseChips({super.key});

  static const presets = [
    ('إيجار', ExpenseCategory.rent, Icons.home_work),
    ('كهرباء', ExpenseCategory.utilities, Icons.bolt),
    ('مياه', ExpenseCategory.utilities, Icons.water_drop),
    ('عمالة', ExpenseCategory.salaries, Icons.engineering),
    ('نقل وشحن', ExpenseCategory.transport, Icons.local_shipping),
    ('صيانة', ExpenseCategory.maintenance, Icons.build),
    ('مستلزمات', ExpenseCategory.supplies, Icons.inventory_2),
    ('مصاريف شخصية', ExpenseCategory.personal, Icons.person),
    ('نثريات', ExpenseCategory.other, Icons.more_horiz),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        for (final (title, cat, icon) in presets)
          ActionChip(
            avatar: Icon(icon, size: 16, color: cat.color),
            label: Text(title),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ExpenseFormScreen(presetTitle: title, presetCategory: cat),
                fullscreenDialog: true,
              ),
            ),
          ),
      ],
    );
  }
}
