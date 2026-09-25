import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/format.dart';
import '../widgets.dart';

class ProductsScreen extends StatelessWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final products = store.products.all..sort((a, b) => a.name.compareTo(b.name));
    final groups = <String, List<Product>>{};
    for (final p in products) {
      groups.putIfAbsent(p.category.isEmpty ? 'بدون تصنيف' : p.category, () => []).add(p);
    }
    final stockValue = products
        .where((p) => p.trackStock)
        .fold<double>(0, (s, p) => s + (p.stock > 0 ? p.stock : 0) * p.cost);
    void open([Product? p]) => Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ProductFormScreen(product: p), fullscreenDialog: true),
    );

    return Scaffold(
      appBar: AppBar(title: const Text('المنتجات والخدمات')),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-products',
        onPressed: open,
        child: const Icon(Icons.add),
      ),
      body: products.isEmpty
          ? EmptyState(
              icon: Icons.inventory_2_outlined,
              title: 'لا توجد منتجات أو خدمات',
              message: 'أضف ما تبيعه لتستخدمه بسرعة في الفواتير وتتابع المخزون',
              actionLabel: 'إضافة',
              onAction: open,
            )
          : ListView(
              padding: const EdgeInsets.only(bottom: 90),
              children: [
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Expanded(
                        child: StatCard(
                          title: 'منتجات وخدمات',
                          value: Fmt.number(products.length),
                          icon: Icons.inventory_2,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: StatCard(
                          title: 'قيمة المخزون (بالتكلفة)',
                          value: Fmt.compactMoney(stockValue),
                          icon: Icons.warehouse,
                          color: Colors.teal,
                          subtitle: products.any((p) => p.isLowStock)
                              ? '${Fmt.number(products.where((p) => p.isLowStock).length)} منخفض'
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
                for (final g in (groups.keys.toList()..sort())) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                    child: Text(g, style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                  for (final p in groups[g]!)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: (p.isService ? Colors.purple : Colors.blue).withValues(alpha: 0.15),
                        child: Icon(
                          p.isService ? Icons.design_services : Icons.inventory_2,
                          color: p.isService ? Colors.purple : Colors.blue,
                        ),
                      ),
                      title: Text(
                        p.name,
                        style: TextStyle(fontWeight: FontWeight.bold, color: p.isActive ? null : Colors.grey),
                      ),
                      subtitle: Text(
                        [
                          if (p.sku.isNotEmpty) p.sku,
                          if (p.cost > 0) 'ربح ${Fmt.percent(p.marginPercent)}',
                          if (!p.isActive) 'موقوف',
                        ].join(' • '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(Fmt.money(p.price), style: const TextStyle(fontWeight: FontWeight.bold)),
                          if (p.trackStock)
                            Pill(
                              'مخزون ${Fmt.number(p.stock)}',
                              color: p.stock <= 0 ? Colors.red : (p.isLowStock ? Colors.orange : Colors.green),
                            ),
                        ],
                      ),
                      onTap: () => open(p),
                    ),
                ],
              ],
            ),
    );
  }
}

class ProductFormScreen extends StatefulWidget {
  const ProductFormScreen({super.key, this.product});
  final Product? product;

  @override
  State<ProductFormScreen> createState() => _ProductFormScreenState();
}

class _ProductFormScreenState extends State<ProductFormScreen> {
  late final Product? _p = widget.product;
  late final _name = TextEditingController(text: _p?.name);
  late final _sku = TextEditingController(text: _p?.sku);
  late final _category = TextEditingController(text: _p?.category);
  late final _notes = TextEditingController(text: _p?.notes);
  late double _price = _p?.price ?? 0;
  late double _cost = _p?.cost ?? 0;
  late bool _isService = _p?.isService ?? false;
  late bool _track = _p?.trackStock ?? false;
  late int _stock = _p?.stock ?? 0;
  late int _low = _p?.lowStockThreshold ?? 5;
  late bool _active = _p?.isActive ?? true;

  @override
  void dispose() {
    for (final c in [_name, _sku, _category, _notes]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      toast(context, 'اكتب الاسم');
      return;
    }
    final store = context.read<AppStore>();
    final p = _p ?? Product();
    p
      ..name = _name.text.trim()
      ..sku = _sku.text.trim()
      ..category = _category.text.trim()
      ..notes = _notes.text.trim()
      ..price = _price
      ..cost = _cost
      ..isService = _isService
      ..trackStock = !_isService && _track
      ..stock = _stock
      ..lowStockThreshold = _low
      ..isActive = _active;
    store.upsert(store.products, p);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 12);
    final categories =
        context.read<AppStore>().products.all.map((p) => p.category).where((c) => c.isNotEmpty).toSet().toList()
          ..sort();
    return Scaffold(
      appBar: AppBar(
        title: Text(_p == null ? 'إضافة منتج / خدمة' : 'تعديل'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('منتج')),
              ButtonSegment(value: true, label: Text('خدمة')),
            ],
            selected: {_isService},
            onSelectionChanged: (s) => setState(() => _isService = s.first),
          ),
          gap,
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم *'),
          ),
          gap,
          TextField(
            controller: _sku,
            decoration: const InputDecoration(labelText: 'الكود / SKU'),
          ),
          gap,
          TextField(
            controller: _category,
            decoration: InputDecoration(
              labelText: 'التصنيف',
              suffixIcon: categories.isEmpty
                  ? null
                  : PopupMenuButton<String>(
                      icon: const Icon(Icons.arrow_drop_down),
                      itemBuilder: (_) => [for (final c in categories) PopupMenuItem(value: c, child: Text(c))],
                      onSelected: (c) => _category.text = c,
                    ),
            ),
          ),
          gap,
          Row(
            children: [
              Expanded(
                child: AmountField(
                  label: 'سعر البيع',
                  value: _price,
                  suffix: Fmt.symbol,
                  onChanged: (v) => setState(() => _price = v),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: AmountField(
                  label: 'التكلفة',
                  value: _cost,
                  suffix: Fmt.symbol,
                  onChanged: (v) => setState(() => _cost = v),
                ),
              ),
            ],
          ),
          if (_price > 0 && _cost > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('هامش الربح: ${Fmt.money(_price - _cost)} (${Fmt.percent((_price - _cost) / _price * 100)})'),
            ),
          if (!_isService) ...[
            const Divider(height: 32),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('متابعة المخزون'),
              value: _track,
              onChanged: (v) => setState(() => _track = v),
            ),
            if (_track) ...[
              _Stepper(label: 'الكمية الحالية', value: _stock, onChanged: (v) => setState(() => _stock = v)),
              _Stepper(label: 'تنبيه عند', value: _low, onChanged: (v) => setState(() => _low = v < 0 ? 0 : v)),
            ],
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('متاح للبيع'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ملاحظات'),
          ),
          const SizedBox(height: 16),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          if (_p != null)
            TextButton(
              onPressed: () async {
                if (await confirm(context, 'حذف؟', _p.name)) {
                  if (!context.mounted) return;
                  final store = context.read<AppStore>();
                  store.delete(store.products, _p.id);
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

class _Stepper extends StatelessWidget {
  const _Stepper({required this.label, required this.value, required this.onChanged});
  final String label;
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Text(label),
      const Spacer(),
      IconButton(onPressed: () => onChanged(value - 1), icon: const Icon(Icons.remove_circle_outline)),
      Text(Fmt.number(value), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
      IconButton(onPressed: () => onChanged(value + 1), icon: const Icon(Icons.add_circle_outline)),
    ],
  );
}
