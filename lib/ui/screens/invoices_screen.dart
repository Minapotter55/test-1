import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../data/prefs.dart';
import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/contact_actions.dart';
import '../../services/format.dart';
import '../../services/invoice_pdf.dart';
import '../widgets.dart';
import 'customers_screen.dart';

class InvoicesScreen extends StatefulWidget {
  const InvoicesScreen({super.key});

  @override
  State<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends State<InvoicesScreen> {
  InvoiceStatus? _filter;
  String _query = '';
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.invoices.all..sort((a, b) => b.issueDate.compareTo(a.issueDate));
    final q = _query.trim().toLowerCase();
    final list = all.where((i) {
      if (_filter != null && i.status != _filter) return false;
      if (q.isEmpty) return true;
      return i.number.toLowerCase().contains(q) ||
          (store.customer(i.customerId)?.name.toLowerCase().contains(q) ?? false);
    }).toList();
    final outstanding = all.where((i) => i.status.isOutstanding).fold<double>(0, (s, i) => s + i.balance);
    final overdue = all.where((i) => i.status == InvoiceStatus.overdue).fold<double>(0, (s, i) => s + i.balance);
    final monthStart = startOfMonth(DateTime.now());
    final collected = store.allPayments
        .where((p) => !p.$1.date.isBefore(monthStart))
        .fold<double>(0, (s, p) => s + p.$1.amount);

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(hintText: 'رقم الفاتورة أو اسم العميل', border: InputBorder.none),
                onChanged: (v) => setState(() => _query = v),
              )
            : const Text('الفواتير'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-invoices',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const InvoiceFormScreen(), fullscreenDialog: true),
        ),
        child: const Icon(Icons.note_add),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long,
              title: 'لا توجد فواتير',
              message: 'أنشئ فاتورة وأرسلها للعميل PDF على واتساب',
              actionLabel: 'فاتورة جديدة',
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const InvoiceFormScreen())),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: Row(
                    children: [
                      Expanded(child: _Tile('مستحقات', outstanding, Colors.orange)),
                      const SizedBox(width: 8),
                      Expanded(child: _Tile('متأخرات', overdue, Colors.red)),
                      const SizedBox(width: 8),
                      Expanded(child: _Tile('تحصيل الشهر', collected, Colors.green)),
                    ],
                  ),
                ),
                ChipsBar<InvoiceStatus>(
                  options: [null, ...InvoiceStatus.values.where((s) => all.any((i) => i.status == s))],
                  selected: _filter,
                  label: (s) =>
                      s == null ? 'الكل' : '${s.label} (${Fmt.number(all.where((i) => i.status == s).length)})',
                  onSelected: (s) => setState(() => _filter = s),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 90),
                    itemCount: list.length,
                    itemBuilder: (_, i) => InvoiceTile(invoice: list[i]),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              Fmt.compactMoney(value),
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    ),
  );
}

class InvoiceTile extends StatelessWidget {
  const InvoiceTile({super.key, required this.invoice, this.showCustomer = true});
  final Invoice invoice;
  final bool showCustomer;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final s = invoice.status;
    final name = store.customer(invoice.customerId)?.name ?? 'بدون عميل';
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: s.color.withValues(alpha: 0.15),
        child: Icon(s.icon, color: s.color),
      ),
      title: Text(showCustomer ? name : invoice.number, style: const TextStyle(fontWeight: FontWeight.bold)),
      subtitle: Text(showCustomer ? '${invoice.number} • ${Fmt.date(invoice.issueDate)}' : Fmt.date(invoice.issueDate)),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(Fmt.money(invoice.total), style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 2),
          Pill(s.label, color: s.color),
        ],
      ),
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: invoice.id))),
    );
  }
}

class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.id});
  final String id;

  Future<File> _pdfFile(BuildContext context, AppStore store, Invoice inv) async {
    final bytes = await InvoicePdf.build(store, inv, accent: context.read<DevicePrefs>().accent.toARGB32());
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/فاتورة-${inv.number.replaceAll('/', '-')}.pdf');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final inv = store.invoices.items[id];
    if (inv == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.receipt_long, title: 'تم حذف الفاتورة'),
      );
    }
    final customer = store.customer(inv.customerId);
    final s = inv.status;

    void save() => store.upsert(store.invoices, inv);

    Future<void> sharePdf() async {
      final file = await _pdfFile(context, store, inv);
      if (context.mounted) await shareFile(context, file, text: 'فاتورة ${inv.number}');
    }

    Future<void> printPdf() async {
      final bytes = await InvoicePdf.build(store, inv, accent: context.read<DevicePrefs>().accent.toARGB32());
      await Printing.layoutPdf(onLayout: (_) async => bytes, name: 'فاتورة ${inv.number}');
    }

    Future<void> remind() async {
      if (customer == null) return;
      final b = StringBuffer('مرحباً ${customer.name}،\n');
      if (s == InvoiceStatus.paid) {
        b.write('نشكركم على سداد الفاتورة رقم ${inv.number} بمبلغ ${Fmt.money(inv.total)}.');
      } else {
        b.write('نود تذكيركم بالفاتورة رقم ${inv.number} بتاريخ ${Fmt.date(inv.issueDate)}\n');
        b.write('المبلغ المتبقي: ${Fmt.money(inv.balance)}\n');
        b.write('تاريخ الاستحقاق: ${Fmt.date(inv.dueDate)}');
      }
      if (store.business.name.isNotEmpty) b.write('\n\n${store.business.name}');
      final ok = await ContactActions.open(
        ContactActions.whatsapp(customer.whatsappNumber, store.business.countryCode, text: b.toString()),
      );
      if (ok) store.logInteraction(customer, InteractionType.whatsapp, 'تذكير بالفاتورة ${inv.number}');
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(inv.number),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => InvoiceFormScreen(invoice: inv), fullscreenDialog: true),
            ),
          ),
          PopupMenuButton<String>(
            itemBuilder: (_) => [
              if (inv.state == InvoiceState.draft) const PopupMenuItem(value: 'issue', child: Text('إصدار الفاتورة')),
              if (s.isOutstanding) const PopupMenuItem(value: 'paid', child: Text('تحديد كمدفوعة بالكامل')),
              const PopupMenuItem(value: 'copy', child: Text('نسخ الفاتورة')),
              if (inv.state == InvoiceState.cancelled)
                const PopupMenuItem(value: 'restore', child: Text('إعادة تفعيل'))
              else
                const PopupMenuItem(value: 'cancel', child: Text('إلغاء الفاتورة')),
              const PopupMenuItem(
                value: 'delete',
                child: Text('حذف', style: TextStyle(color: Colors.red)),
              ),
            ],
            onSelected: (v) async {
              switch (v) {
                case 'issue':
                  inv.state = InvoiceState.issued;
                  save();
                case 'paid':
                  inv.payments.add(Payment(amount: inv.balance));
                  save();
                case 'print':
                  await printPdf();
                case 'copy':
                  final copy = Invoice(
                    number: store.takeInvoiceNumber(),
                    customerId: inv.customerId,
                    dueDate: DateTime.now().add(Duration(days: store.business.defaultDueDays)),
                    state: InvoiceState.draft,
                    discount: inv.discount,
                    taxRate: inv.taxRate,
                    notes: inv.notes,
                    items: [
                      for (final i in inv.items)
                        InvoiceItem(name: i.name, quantity: i.quantity, unitPrice: i.unitPrice, productId: i.productId),
                    ],
                  );
                  store.upsert(store.invoices, copy);
                  if (context.mounted) {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => InvoiceDetailScreen(id: copy.id)),
                    );
                  }
                case 'cancel':
                  inv.state = InvoiceState.cancelled;
                  save();
                case 'restore':
                  inv.state = InvoiceState.issued;
                  save();
                case 'delete':
                  if (await confirm(context, 'حذف الفاتورة؟', 'سيتم حذف الفاتورة وكل المدفوعات المسجلة عليها.')) {
                    store.delete(store.invoices, inv.id);
                    if (context.mounted) Navigator.pop(context);
                  }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Center(
            child: Pill(s.label, color: s.color, icon: s.icon),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              Fmt.money(inv.total),
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          if (inv.state == InvoiceState.issued && inv.total > 0) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: (inv.paidAmount / inv.total).clamp(0, 1),
              color: Colors.green,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
            ),
            const SizedBox(height: 4),
            Center(
              child: Text(
                'مدفوع ${Fmt.money(inv.paidAmount)} • متبقي ${Fmt.money(inv.balance)}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              _Action('PDF', Icons.picture_as_pdf, Colors.blue, sharePdf),
              _Action('طباعة', Icons.print, Colors.indigo, printPdf),
              _Action('تذكير واتساب', Icons.chat, Colors.green, customer == null ? null : remind),
              _Action(
                'تسجيل دفعة',
                Icons.payments,
                Colors.orange,
                inv.state == InvoiceState.issued && inv.balance > 0 ? () => showPaymentSheet(context, inv) : null,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Column(
              children: [
                if (customer != null)
                  ListTile(
                    leading: Avatar(name: customer.name, color: customer.status.color, size: 36),
                    title: Text(customer.name),
                    subtitle: customer.phone.isEmpty ? null : Text(customer.phone),
                    trailing: const Icon(Icons.chevron_left),
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: customer.id)),
                    ),
                  ),
                ListTile(dense: true, title: const Text('تاريخ الإصدار'), trailing: Text(Fmt.date(inv.issueDate))),
                ListTile(
                  dense: true,
                  title: const Text('تاريخ الاستحقاق'),
                  trailing: Text(
                    Fmt.date(inv.dueDate),
                    style: TextStyle(color: s == InvoiceStatus.overdue ? Colors.red : null),
                  ),
                ),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                const ListTile(
                  title: Text('البنود', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                for (final item in inv.items)
                  ListTile(
                    dense: true,
                    title: Text(item.name),
                    subtitle: Text('${Fmt.number(item.quantity)} × ${Fmt.money(item.unitPrice)}'),
                    trailing: Text(Fmt.money(item.total)),
                  ),
                const Divider(),
                _row('المجموع الفرعي', Fmt.money(inv.subtotal)),
                if (inv.discount > 0) _row('الخصم', '- ${Fmt.money(inv.discount)}'),
                if (inv.taxRate > 0) _row('الضريبة ${Fmt.number(inv.taxRate)}٪', Fmt.money(inv.taxAmount)),
                _row('الإجمالي', Fmt.money(inv.total), bold: true),
                const SizedBox(height: 8),
              ],
            ),
          ),
          Card(
            child: Column(
              children: [
                ListTile(
                  title: Text(
                    'المدفوعات (${Fmt.money(inv.paidAmount)})',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                if (inv.payments.isEmpty) const ListTile(dense: true, title: Text('لا توجد مدفوعات')),
                for (final p in [...inv.payments]..sort((a, b) => b.date.compareTo(a.date)))
                  ListTile(
                    dense: true,
                    leading: Icon(p.method.icon, color: Colors.green),
                    title: Text(p.method.label),
                    subtitle: Text(Fmt.date(p.date) + (p.note.isEmpty ? '' : ' • ${p.note}')),
                    trailing: Text(
                      Fmt.money(p.amount),
                      style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                    onLongPress: () async {
                      if (await confirm(context, 'حذف الدفعة؟', Fmt.money(p.amount))) {
                        inv.payments.removeWhere((x) => x.id == p.id);
                        save();
                      }
                    },
                  ),
                if (inv.payments.isNotEmpty)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Text('اضغط مطولاً على الدفعة لحذفها', style: TextStyle(fontSize: 11)),
                  ),
              ],
            ),
          ),
          if (inv.notes.isNotEmpty)
            Card(
              child: ListTile(title: const Text('ملاحظات'), subtitle: Text(inv.notes)),
            ),
        ],
      ),
    );
  }

  Widget _row(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: TextStyle(fontWeight: bold ? FontWeight.bold : null)),
        ),
        Text(
          value,
          style: TextStyle(fontWeight: bold ? FontWeight.bold : null, fontSize: bold ? 16 : null),
        ),
      ],
    ),
  );
}

class _Action extends StatelessWidget {
  const _Action(this.label, this.icon, this.color, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = onTap == null ? Colors.grey : color;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            children: [
              CircleAvatar(
                backgroundColor: c.withValues(alpha: 0.15),
                child: Icon(icon, color: c),
              ),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

void showPaymentSheet(BuildContext context, Invoice inv) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _PaymentSheet(invoice: inv),
  );
}

class _PaymentSheet extends StatefulWidget {
  const _PaymentSheet({required this.invoice});
  final Invoice invoice;

  @override
  State<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends State<_PaymentSheet> {
  late double _amount = widget.invoice.balance;
  PaymentMethod _method = PaymentMethod.cash;
  DateTime _date = DateTime.now();
  final _note = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inv = widget.invoice;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تسجيل دفعة — المتبقي ${Fmt.money(inv.balance)}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          AmountField(label: 'المبلغ', value: _amount, suffix: Fmt.symbol, onChanged: (v) => _amount = v),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: () => setState(() => _amount = inv.balance), child: const Text('كامل المتبقي')),
              TextButton(
                onPressed: () => setState(() => _amount = (inv.balance / 2).roundToDouble()),
                child: const Text('النصف'),
              ),
            ],
          ),
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
            decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: () {
              if (_amount <= 0) return;
              final store = context.read<AppStore>();
              inv.payments.add(Payment(amount: _amount, date: _date, method: _method, note: _note.text.trim()));
              store.upsert(store.invoices, inv);
              Navigator.pop(context);
            },
            child: const Text('حفظ الدفعة'),
          ),
        ],
      ),
    );
  }
}

class InvoiceFormScreen extends StatefulWidget {
  const InvoiceFormScreen({super.key, this.invoice, this.customerId});
  final Invoice? invoice;
  final String? customerId;

  @override
  State<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends State<InvoiceFormScreen> {
  late final AppStore _store = context.read<AppStore>();
  late final Invoice? _inv = widget.invoice;
  late String? _customerId = _inv?.customerId ?? widget.customerId;
  late final _number = TextEditingController(text: _inv?.number ?? _store.peekInvoiceNumber());
  late DateTime _issue = _inv?.issueDate ?? DateTime.now();
  late DateTime _due = _inv?.dueDate ?? DateTime.now().add(Duration(days: _store.business.defaultDueDays));
  late double _discount = _inv?.discount ?? 0;
  late double _tax = _inv?.taxRate ?? _store.business.defaultTaxRate;
  late final _notes = TextEditingController(text: _inv?.notes);
  late final List<_DraftItem> _items = [
    for (final i in _inv?.items ?? <InvoiceItem>[]) _DraftItem(i.name, i.quantity, i.unitPrice, i.productId),
  ];

  double get _subtotal => _items.fold(0, (s, i) => s + i.qty * i.price);
  double get _taxable => (_subtotal - _discount).clamp(0, double.infinity).toDouble();
  double get _total => _taxable + _taxable * _tax / 100;

  @override
  void dispose() {
    _number.dispose();
    _notes.dispose();
    for (final i in _items) {
      i.name.dispose();
    }
    super.dispose();
  }

  Future<void> _pickProduct() async {
    final products = _store.products.all.where((p) => p.isActive).toList()..sort((a, b) => a.name.compareTo(b.name));
    if (products.isEmpty) {
      toast(context, 'أضف منتجاتك وخدماتك أولاً من المزيد ← المنتجات والخدمات');
      return;
    }
    final p = await showModalBottomSheet<Product>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        children: [
          for (final p in products)
            ListTile(
              leading: Icon(p.isService ? Icons.design_services : Icons.inventory_2),
              title: Text(p.name),
              subtitle: p.trackStock ? Text('المخزون: ${Fmt.number(p.stock)}') : null,
              trailing: Text(Fmt.money(p.price)),
              onTap: () => Navigator.pop(ctx, p),
            ),
        ],
      ),
    );
    if (p != null) setState(() => _items.add(_DraftItem(p.name, 1, p.price, p.id)));
  }

  void _save({required bool draft}) {
    final items = [
      for (final i in _items)
        if (i.name.text.trim().isNotEmpty)
          InvoiceItem(name: i.name.text.trim(), quantity: i.qty, unitPrice: i.price, productId: i.productId),
    ];
    if (items.isEmpty) {
      toast(context, 'أضف بنداً واحداً على الأقل');
      return;
    }
    final isNew = _inv == null;
    final inv = _inv ?? Invoice();
    var number = _number.text.trim();
    if (isNew && number == _store.peekInvoiceNumber()) number = _store.takeInvoiceNumber();
    inv
      ..number = number
      ..customerId = _customerId
      ..issueDate = _issue
      ..dueDate = _due.isBefore(_issue) ? _issue : _due
      ..discount = _discount
      ..taxRate = _tax
      ..notes = _notes.text.trim()
      ..items = items;
    if (draft) {
      inv.state = InvoiceState.draft;
    } else if (inv.state == InvoiceState.draft) {
      inv.state = InvoiceState.issued;
    }
    _store.upsert(_store.invoices, inv);

    if (isNew) {
      // Deduct stock for tracked products.
      for (final item in items) {
        final p = item.productId == null ? null : _store.products.items[item.productId];
        if (p != null && p.trackStock) {
          p.stock -= item.quantity.round();
          _store.upsert(_store.products, p);
        }
      }
    }
    final c = _store.customer(_customerId);
    if (!draft && c != null && (c.status == CustomerStatus.lead || c.status == CustomerStatus.prospect)) {
      c.status = CustomerStatus.active;
      _store.upsert(_store.customers, c);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final canDraft = _inv == null || _inv.state == InvoiceState.draft;
    return Scaffold(
      appBar: AppBar(
        title: Text(_inv == null ? 'فاتورة جديدة' : 'تعديل الفاتورة'),
        actions: [TextButton(onPressed: () => _save(draft: false), child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CustomerDropdown(value: _customerId, onChanged: (v) => setState(() => _customerId = v)),
          gap,
          TextField(
            controller: _number,
            decoration: const InputDecoration(labelText: 'رقم الفاتورة'),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event),
                  label: Text('الإصدار: ${Fmt.date(_issue)}'),
                  onPressed: () async {
                    final d = await pickDate(context, _issue);
                    if (d != null) setState(() => _issue = d);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_available),
                  label: Text('الاستحقاق: ${Fmt.date(_due)}'),
                  onPressed: () async {
                    final d = await pickDate(context, _due, first: _issue);
                    if (d != null) setState(() => _due = d);
                  },
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Text('البنود', style: Theme.of(context).textTheme.titleMedium),
          for (final item in _items)
            Card(
              key: ObjectKey(item),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: item.name,
                            decoration: const InputDecoration(labelText: 'المنتج أو الخدمة'),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => setState(() {
                            _items.remove(item);
                            item.name.dispose();
                          }),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: AmountField(
                            label: 'الكمية',
                            value: item.qty,
                            onChanged: (v) => setState(() => item.qty = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: AmountField(
                            label: 'السعر',
                            value: item.price,
                            onChanged: (v) => setState(() => item.price = v),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(Fmt.money(item.qty * item.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: _pickProduct,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('من المنتجات'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => setState(() => _items.add(_DraftItem('', 1, 0, null))),
                  icon: const Icon(Icons.add),
                  label: const Text('بند يدوي'),
                ),
              ),
            ],
          ),
          const Divider(height: 32),
          Row(
            children: [
              Expanded(
                child: AmountField(
                  label: 'الخصم (مبلغ)',
                  value: _discount,
                  onChanged: (v) => setState(() => _discount = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AmountField(
                  label: 'الضريبة',
                  suffix: '٪',
                  value: _tax,
                  onChanged: (v) => setState(() => _tax = v),
                ),
              ),
            ],
          ),
          gap,
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(children: [const Text('المجموع الفرعي'), const Spacer(), Text(Fmt.money(_subtotal))]),
                  Row(
                    children: [
                      const Text('الإجمالي', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                      const Spacer(),
                      Text(Fmt.money(_total), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          gap,
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات تظهر في الفاتورة (مثل بيانات التحويل)'),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => _save(draft: false),
            child: Text(canDraft ? 'إصدار الفاتورة' : 'حفظ التعديلات'),
          ),
          if (canDraft) TextButton(onPressed: () => _save(draft: true), child: const Text('حفظ كمسودة')),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _DraftItem {
  _DraftItem(String name, this.qty, this.price, this.productId) : name = TextEditingController(text: name);
  final TextEditingController name;
  double qty;
  double price;
  final String? productId;
}
