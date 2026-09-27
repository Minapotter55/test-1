import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/store.dart';
import '../../models/models.dart';
import '../../services/contact_actions.dart';
import '../../services/format.dart';
import '../widgets.dart';
import 'client_accounts_screen.dart';
import 'deals_screen.dart';
import 'invoices_screen.dart';
import 'tasks_screen.dart';

enum _Sort { newest, name, lastContact, revenue, balance }

extension on _Sort {
  String get label => switch (this) {
    _Sort.newest => 'الأحدث',
    _Sort.name => 'الاسم',
    _Sort.lastContact => 'آخر تواصل',
    _Sort.revenue => 'الأكثر شراءً',
    _Sort.balance => 'الأعلى مستحقات',
  };
}

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  String _query = '';
  CustomerStatus? _status;
  String? _tag;
  bool _favorites = false;
  _Sort _sort = _Sort.newest;
  bool _searching = false;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final all = store.customers.all;
    final tags = {for (final c in all) ...c.tags}.toList()..sort();
    final q = _query.trim().toLowerCase();

    var list = all.where((c) {
      if (_status != null && c.status != _status) return false;
      if (_tag != null && !c.tags.contains(_tag)) return false;
      if (_favorites && !c.isFavorite) return false;
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.company.toLowerCase().contains(q) ||
          c.phone.contains(q) ||
          c.email.toLowerCase().contains(q) ||
          c.city.toLowerCase().contains(q) ||
          c.sector.toLowerCase().contains(q) ||
          c.contactPerson.toLowerCase().contains(q) ||
          c.tags.any((t) => t.toLowerCase().contains(q));
    }).toList();

    switch (_sort) {
      case _Sort.newest:
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      case _Sort.name:
        list.sort((a, b) => a.name.compareTo(b.name));
      case _Sort.lastContact:
        list.sort((a, b) => (b.lastContactAt ?? DateTime(1970)).compareTo(a.lastContactAt ?? DateTime(1970)));
      case _Sort.revenue:
        list.sort((a, b) => store.totalPaidBy(b.id).compareTo(store.totalPaidBy(a.id)));
      case _Sort.balance:
        list.sort((a, b) => store.balanceOf(b.id).compareTo(store.balanceOf(a.id)));
    }

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'ابحث بالاسم أو الهاتف أو الشركة',
                  border: InputBorder.none,
                ),
                onChanged: (v) => setState(() => _query = v),
              )
            : Text('العملاء (${Fmt.number(all.length)})'),
        actions: [
          IconButton(
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () => setState(() {
              _searching = !_searching;
              _query = '';
            }),
          ),
          PopupMenuButton<Object>(
            icon: const Icon(Icons.filter_list),
            itemBuilder: (_) => [
              const PopupMenuItem(enabled: false, child: Text('ترتيب حسب')),
              for (final s in _Sort.values) CheckedPopupMenuItem(value: s, checked: _sort == s, child: Text(s.label)),
              const PopupMenuDivider(),
              CheckedPopupMenuItem(value: 'fav', checked: _favorites, child: const Text('المفضلين فقط')),
              if (tags.isNotEmpty) ...[
                const PopupMenuDivider(),
                const PopupMenuItem(enabled: false, child: Text('الوسم')),
                CheckedPopupMenuItem(value: '#', checked: _tag == null, child: const Text('كل الوسوم')),
                for (final t in tags) CheckedPopupMenuItem(value: '#$t', checked: _tag == t, child: Text(t)),
              ],
            ],
            onSelected: (v) => setState(() {
              if (v is _Sort) _sort = v;
              if (v == 'fav') _favorites = !_favorites;
              if (v is String && v.startsWith('#')) _tag = v.length == 1 ? null : v.substring(1);
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'fab-customers',
        onPressed: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CustomerFormScreen(), fullscreenDialog: true),
        ),
        child: const Icon(Icons.person_add_alt_1),
      ),
      body: all.isEmpty
          ? EmptyState(
              icon: Icons.people_outline,
              title: 'لا يوجد عملاء بعد',
              message: 'أضف أول عميل لتبدأ في متابعة مبيعاتك',
              actionLabel: 'إضافة عميل',
              onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerFormScreen())),
            )
          : Column(
              children: [
                ChipsBar<CustomerStatus>(
                  options: [null, ...CustomerStatus.values.where((s) => all.any((c) => c.status == s))],
                  selected: _status,
                  label: (s) => s == null
                      ? 'الكل (${Fmt.number(all.length)})'
                      : '${s.label} (${Fmt.number(all.where((c) => c.status == s).length)})',
                  onSelected: (s) => setState(() => _status = s),
                ),
                Expanded(
                  child: list.isEmpty
                      ? const EmptyState(icon: Icons.search_off, title: 'لا توجد نتائج')
                      : ListView.builder(
                          padding: const EdgeInsets.only(bottom: 90),
                          itemCount: list.length,
                          itemBuilder: (_, i) => CustomerTile(customer: list[i]),
                        ),
                ),
              ],
            ),
    );
  }
}

class CustomerTile extends StatelessWidget {
  const CustomerTile({super.key, required this.customer});
  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final store = context.read<AppStore>();
    final balance = store.balanceOf(customer.id);
    return ListTile(
      leading: Avatar(name: customer.name, color: customer.status.color),
      title: Row(
        children: [
          Flexible(
            child: Text(
              customer.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          if (customer.isFavorite)
            const Padding(
              padding: EdgeInsets.only(right: 4),
              child: Icon(Icons.star, size: 16, color: Colors.amber),
            ),
        ],
      ),
      subtitle: Wrap(
        spacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (customer.sector.isNotEmpty) Pill(customer.sector, color: Colors.indigo),
          Pill(customer.status.label, color: customer.status.color),
          if (customer.contractExpired)
            const Pill('العقد انتهى', color: Colors.red, icon: Icons.event_busy)
          else if (customer.contractEndingSoon)
            const Pill('العقد قرب يخلص', color: Colors.orange, icon: Icons.event),
          if (customer.feeCycle == FeeCycle.monthly && customer.fee > 0)
            Text('${Fmt.compactMoney(customer.fee)}/شهر', style: const TextStyle(fontSize: 12)),
          if (customer.lastContactAt != null)
            Text(Fmt.relative(customer.lastContactAt!), style: const TextStyle(fontSize: 11)),
        ],
      ),
      trailing: balance > 0
          ? Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  Fmt.compactMoney(balance),
                  style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                ),
                const Text('مستحق', style: TextStyle(fontSize: 11)),
              ],
            )
          : null,
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CustomerDetailScreen(id: customer.id))),
    );
  }
}

class CustomerDetailScreen extends StatelessWidget {
  const CustomerDetailScreen({super.key, required this.id});
  final String id;

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final c = store.customer(id);
    if (c == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const EmptyState(icon: Icons.person_off, title: 'تم حذف العميل'),
      );
    }
    final code = store.business.countryCode;
    final invoices = store.invoicesOf(c.id);
    final deals = store.dealsOf(c.id)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final tasks = store.tasksOf(c.id)..sort((a, b) => a.isDone == b.isDone ? 0 : (a.isDone ? 1 : -1));
    final log = store.interactionsOf(c.id);

    void open(Widget page) => Navigator.push(context, MaterialPageRoute(builder: (_) => page, fullscreenDialog: true));

    Future<void> contact(Uri? uri, InteractionType? type) async {
      final ok = await ContactActions.open(uri);
      if (ok && type != null) store.logInteraction(c, type, '');
    }

    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: Text(c.name),
          actions: [
            IconButton(
              icon: Icon(c.isFavorite ? Icons.star : Icons.star_border, color: c.isFavorite ? Colors.amber : null),
              onPressed: () {
                c.isFavorite = !c.isFavorite;
                store.upsert(store.customers, c);
              },
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => open(CustomerFormScreen(customer: c)),
            ),
            PopupMenuButton<String>(
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'log', child: Text('تسجيل تواصل')),
                PopupMenuItem(value: 'task', child: Text('مهمة / تذكير جديد')),
                PopupMenuItem(value: 'deal', child: Text('صفقة جديدة')),
                PopupMenuItem(value: 'invoice', child: Text('فاتورة جديدة')),
                PopupMenuItem(
                  value: 'delete',
                  child: Text('حذف العميل', style: TextStyle(color: Colors.red)),
                ),
              ],
              onSelected: (v) async {
                switch (v) {
                  case 'log':
                    showInteractionSheet(context, c);
                  case 'task':
                    open(TaskFormScreen(customerId: c.id));
                  case 'deal':
                    open(DealFormScreen(customerId: c.id));
                  case 'invoice':
                    open(InvoiceFormScreen(customerId: c.id));
                  case 'delete':
                    if (await confirm(context, 'حذف العميل؟', 'سيتم حذف ${c.name} وكل فواتيره وصفقاته وسجل التواصل.')) {
                      store.deleteCustomer(c);
                      if (context.mounted) Navigator.pop(context);
                    }
                }
              },
            ),
          ],
        ),
        body: NestedScrollView(
          headerSliverBuilder: (context, _) => [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Avatar(name: c.name, color: c.status.color, size: 80),
                    const SizedBox(height: 8),
                    Text(c.name, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                    if (c.sector.isNotEmpty || c.company.isNotEmpty)
                      Text([c.sector, c.company].where((x) => x.isNotEmpty).join(' • ')),
                    if (c.contactPerson.isNotEmpty)
                      Text(
                        '👤 ${c.contactPerson}${c.contactRole.isEmpty ? '' : ' — ${c.contactRole}'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    if (c.contractExpired || c.contractEndingSoon)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Pill(
                          c.contractExpired
                              ? 'العقد انتهى ${Fmt.date(c.contractEnd!)}'
                              : 'العقد بينتهي ${Fmt.relative(c.contractEnd!)}',
                          color: c.contractExpired ? Colors.red : Colors.orange,
                          icon: Icons.event_busy,
                        ),
                      ),
                    const SizedBox(height: 6),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        PopupMenuButton<CustomerStatus>(
                          tooltip: 'تغيير الحالة',
                          itemBuilder: (_) => [
                            for (final s in CustomerStatus.values) PopupMenuItem(value: s, child: Text(s.label)),
                          ],
                          onSelected: (s) {
                            c.status = s;
                            store.upsert(store.customers, c);
                          },
                          child: Pill(c.status.label, color: c.status.color, icon: c.status.icon),
                        ),
                        const SizedBox(width: 8),
                        for (var i = 1; i <= 5; i++)
                          GestureDetector(
                            onTap: () {
                              c.rating = c.rating == i ? 0 : i;
                              store.upsert(store.customers, c);
                            },
                            child: Icon(i <= c.rating ? Icons.star : Icons.star_border, size: 18, color: Colors.amber),
                          ),
                      ],
                    ),
                    if (c.tags.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          children: [
                            for (final t in c.tags)
                              Text('#$t', style: TextStyle(color: Theme.of(context).colorScheme.primary)),
                          ],
                        ),
                      ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        _ActionButton(
                          'اتصال',
                          Icons.call,
                          Colors.green,
                          ContactActions.call(c.phone),
                          () => contact(ContactActions.call(c.phone), InteractionType.call),
                        ),
                        _ActionButton(
                          'واتساب',
                          Icons.chat,
                          Colors.teal,
                          ContactActions.whatsapp(c.whatsappNumber, code),
                          () => contact(ContactActions.whatsapp(c.whatsappNumber, code), InteractionType.whatsapp),
                        ),
                        _ActionButton(
                          'رسالة',
                          Icons.sms,
                          Colors.blue,
                          ContactActions.sms(c.phone),
                          () => contact(ContactActions.sms(c.phone), null),
                        ),
                        _ActionButton(
                          'بريد',
                          Icons.email,
                          Colors.orange,
                          ContactActions.email(c.email),
                          () => contact(ContactActions.email(c.email), InteractionType.email),
                        ),
                        _ActionButton(
                          'خريطة',
                          Icons.map,
                          Colors.red,
                          ContactActions.maps('${c.address} ${c.city}'),
                          () => contact(ContactActions.maps('${c.address} ${c.city}'), null),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Builder(
                      builder: (context) {
                        final acc = store.accountOf(c);
                        return Row(
                          children: [
                            Expanded(child: _MiniStat('المحصّل', Fmt.compactMoney(acc.income), Colors.green)),
                            const SizedBox(width: 6),
                            Expanded(child: _MiniStat('المصروف عليه', Fmt.compactMoney(acc.spent), Colors.red)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: _MiniStat(
                                'الربح',
                                Fmt.compactMoney(acc.profit),
                                acc.profit >= 0 ? Colors.teal : Colors.red,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: _MiniStat('المستحق', Fmt.compactMoney(acc.balance), Colors.orange)),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SliverToBoxAdapter(
              child: TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  Tab(text: 'الحسابات'),
                  Tab(text: 'التواصل'),
                  Tab(text: 'الفواتير'),
                  Tab(text: 'المهام'),
                  Tab(text: 'الصفقات'),
                  Tab(text: 'البيانات'),
                ],
              ),
            ),
          ],
          body: TabBarView(
            children: [
              ClientAccountTab(customer: c),
              ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_comment_outlined),
                    title: const Text('تسجيل تواصل جديد'),
                    onTap: () => showInteractionSheet(context, c),
                  ),
                  if (log.isEmpty) const ListTile(title: Text('لا يوجد سجل تواصل بعد')),
                  for (final i in log)
                    Dismissible(
                      key: ValueKey(i.id),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        color: Colors.red,
                        alignment: AlignmentDirectional.centerEnd,
                        padding: const EdgeInsets.all(16),
                        child: const Icon(Icons.delete, color: Colors.white),
                      ),
                      onDismissed: (_) => store.delete(store.interactions, i.id),
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: i.type.color.withValues(alpha: 0.15),
                          child: Icon(i.type.icon, color: i.type.color, size: 20),
                        ),
                        title: Text(i.type.label),
                        subtitle: i.summary.isEmpty ? null : Text(i.summary),
                        trailing: Text(Fmt.dateTime(i.date), style: const TextStyle(fontSize: 11)),
                      ),
                    ),
                ],
              ),
              ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.note_add_outlined),
                    title: const Text('فاتورة جديدة'),
                    onTap: () => open(InvoiceFormScreen(customerId: c.id)),
                  ),
                  for (final inv in invoices) InvoiceTile(invoice: inv, showCustomer: false),
                ],
              ),
              ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.add_task),
                    title: const Text('مهمة / تذكير جديد'),
                    onTap: () => open(TaskFormScreen(customerId: c.id)),
                  ),
                  for (final t in tasks) TaskTile(task: t, showCustomer: false),
                ],
              ),
              ListView(
                children: [
                  ListTile(
                    leading: const Icon(Icons.handshake_outlined),
                    title: const Text('صفقة جديدة'),
                    onTap: () => open(DealFormScreen(customerId: c.id)),
                  ),
                  for (final d in deals) DealTile(deal: d, showCustomer: false),
                ],
              ),
              ListView(
                children: [
                  InfoTile('القطاع', c.sector, icon: Icons.local_hospital_outlined),
                  InfoTile('الفرع / الجهة', c.company, icon: Icons.account_tree_outlined),
                  InfoTile(
                    'المسؤول',
                    [c.contactPerson, c.contactRole].where((x) => x.isNotEmpty).join(' — '),
                    icon: Icons.badge_outlined,
                  ),
                  InfoTile(
                    'السعر',
                    c.feeCycle == FeeCycle.none || c.fee == 0 ? '' : '${c.feeCycle.label}: ${Fmt.money(c.fee)}',
                    icon: Icons.sell_outlined,
                  ),
                  InfoTile(
                    'بداية التعاقد',
                    c.contractStart == null ? '' : Fmt.date(c.contractStart!),
                    icon: Icons.event,
                  ),
                  InfoTile(
                    'نهاية التعاقد',
                    c.contractEnd == null ? '' : Fmt.date(c.contractEnd!),
                    icon: Icons.event_busy,
                  ),
                  InfoTile('الخدمات المتفق عليها', c.services.join('، '), icon: Icons.medical_services_outlined),
                  InfoTile('الهاتف', c.phone, icon: Icons.phone),
                  InfoTile('واتساب', c.whatsapp, icon: Icons.chat),
                  InfoTile('البريد', c.email, icon: Icons.email),
                  InfoTile('المدينة', c.city, icon: Icons.location_city),
                  InfoTile('العنوان', c.address, icon: Icons.place),
                  InfoTile('المصدر', c.source, icon: Icons.call_received),
                  InfoTile('تاريخ الميلاد', c.birthday == null ? '' : Fmt.date(c.birthday!), icon: Icons.cake),
                  InfoTile('عميل منذ', Fmt.date(c.createdAt), icon: Icons.calendar_today),
                  InfoTile(
                    'آخر تواصل',
                    c.lastContactAt == null ? '' : Fmt.relative(c.lastContactAt!),
                    icon: Icons.history,
                  ),
                  for (final f in c.customFields) InfoTile(f.key, f.value, icon: Icons.label_outline),
                  InfoTile('ملاحظات', c.notes, icon: Icons.notes),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton(this.label, this.icon, this.color, this.uri, this.onTap);
  final String label;
  final IconData icon;
  final Color color;
  final Uri? uri;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = uri != null;
    final c = enabled ? color : Colors.grey;
    return Expanded(
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            CircleAvatar(
              backgroundColor: c.withValues(alpha: 0.15),
              child: Icon(icon, color: c),
            ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat(this.label, this.value, this.color);
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
      child: Column(
        children: [
          FittedBox(
            child: Text(
              value,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Text(label, style: const TextStyle(fontSize: 11), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}

void showInteractionSheet(BuildContext context, Customer c) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => _InteractionSheet(customer: c),
  );
}

class _InteractionSheet extends StatefulWidget {
  const _InteractionSheet({required this.customer});
  final Customer customer;

  @override
  State<_InteractionSheet> createState() => _InteractionSheetState();
}

class _InteractionSheetState extends State<_InteractionSheet> {
  InteractionType _type = InteractionType.call;
  final _summary = TextEditingController();
  DateTime _date = DateTime.now();
  bool _followUp = false;
  DateTime _followUpAt = DateTime.now().add(const Duration(days: 3));

  @override
  void dispose() {
    _summary.dispose();
    super.dispose();
  }

  void _save() {
    final store = context.read<AppStore>();
    store.logInteraction(widget.customer, _type, _summary.text.trim(), date: _date);
    if (_followUp) {
      store.upsert(
        store.tasks,
        TaskItem(
          title: 'متابعة مع ${widget.customer.name}',
          notes: _summary.text.trim(),
          dueDate: _followUpAt,
          customerId: widget.customer.id,
        ),
      );
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.of(context).viewInsets.bottom + 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('تسجيل تواصل مع ${widget.customer.name}', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          Wrap(
            spacing: 6,
            children: [
              for (final t in InteractionType.values)
                ChoiceChip(
                  avatar: Icon(t.icon, size: 16),
                  label: Text(t.label),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _summary,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'ماذا حدث؟'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: Text(Fmt.dateTime(_date)),
            onTap: () async {
              final d = await pickDateTime(context, _date);
              if (d != null) setState(() => _date = d);
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('إنشاء تذكير متابعة'),
            value: _followUp,
            onChanged: (v) => setState(() => _followUp = v),
          ),
          if (_followUp)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.alarm),
              title: Text('موعد المتابعة: ${Fmt.dateTime(_followUpAt)}'),
              onTap: () async {
                final d = await pickDateTime(context, _followUpAt);
                if (d != null) setState(() => _followUpAt = d);
              },
            ),
          const SizedBox(height: 8),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
        ],
      ),
    );
  }
}

class CustomerFormScreen extends StatefulWidget {
  const CustomerFormScreen({super.key, this.customer});
  final Customer? customer;

  @override
  State<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends State<CustomerFormScreen> {
  late final AppStore _store = context.read<AppStore>();
  late final Customer? _c = widget.customer;
  late final _name = TextEditingController(text: _c?.name);
  late final _company = TextEditingController(text: _c?.company);
  late final _sector = TextEditingController(text: _c?.sector);
  late final _contact = TextEditingController(text: _c?.contactPerson);
  late final _contactRole = TextEditingController(text: _c?.contactRole);
  late final _phone = TextEditingController(text: _c?.phone);
  late final _whatsapp = TextEditingController(text: _c?.whatsapp);
  late final _email = TextEditingController(text: _c?.email);
  late final _city = TextEditingController(text: _c?.city);
  late final _address = TextEditingController(text: _c?.address);
  late final _source = TextEditingController(text: _c?.source);
  late final _notes = TextEditingController(text: _c?.notes);
  late final _tag = TextEditingController();
  late CustomerStatus _status = _c?.status ?? CustomerStatus.active;
  late int _rating = _c?.rating ?? 0;
  late final List<String> _tags = [...?_c?.tags];
  late final List<String> _services = [...?_c?.services];
  late DateTime? _birthday = _c?.birthday;
  late DateTime? _contractStart = _c?.contractStart;
  late DateTime? _contractEnd = _c?.contractEnd;
  late double _fee = _c?.fee ?? 0;
  late FeeCycle _feeCycle = _c?.feeCycle ?? FeeCycle.monthly;
  late int _billingDay = _c?.billingDay ?? 1;

  /// Template fields (from "تخصيص الخانات") first, then the client's own extra fields.
  late final List<(TextEditingController, TextEditingController, bool)> _fields = () {
    final existing = {for (final f in _c?.customFields ?? <CustomField>[]) f.key: f.value};
    final templates = _store.business.clientFieldTemplates;
    return [
      for (final t in templates) (TextEditingController(text: t), TextEditingController(text: existing[t] ?? ''), true),
      for (final e in existing.entries)
        if (!templates.contains(e.key))
          (TextEditingController(text: e.key), TextEditingController(text: e.value), false),
    ];
  }();

  @override
  void dispose() {
    for (final c in [
      _name,
      _company,
      _sector,
      _contact,
      _contactRole,
      _phone,
      _whatsapp,
      _email,
      _city,
      _address,
      _source,
      _notes,
      _tag,
    ]) {
      c.dispose();
    }
    for (final f in _fields) {
      f.$1.dispose();
      f.$2.dispose();
    }
    super.dispose();
  }

  void _addTag() {
    final t = _tag.text.trim();
    if (t.isEmpty || _tags.contains(t)) return;
    setState(() {
      _tags.add(t);
      _tag.clear();
    });
  }

  void _save() {
    if (_name.text.trim().isEmpty) {
      toast(context, 'اكتب اسم العميل أو الجهة');
      return;
    }
    final c = _c ?? Customer();
    final sector = _sector.text.trim();
    c
      ..name = _name.text.trim()
      ..company = _company.text.trim()
      ..sector = sector
      ..contactPerson = _contact.text.trim()
      ..contactRole = _contactRole.text.trim()
      ..phone = _phone.text.trim()
      ..whatsapp = _whatsapp.text.trim()
      ..email = _email.text.trim()
      ..city = _city.text.trim()
      ..address = _address.text.trim()
      ..source = _source.text.trim()
      ..notes = _notes.text.trim()
      ..status = _status
      ..rating = _rating
      ..tags = _tags
      ..services = _services
      ..birthday = _birthday
      ..contractStart = _contractStart
      ..contractEnd = _contractEnd
      ..fee = _feeCycle == FeeCycle.none ? 0 : _fee
      ..feeCycle = _feeCycle
      ..billingDay = _billingDay
      ..customFields = [
        for (final f in _fields)
          if (f.$1.text.trim().isNotEmpty && f.$2.text.trim().isNotEmpty)
            CustomField(key: f.$1.text.trim(), value: f.$2.text.trim()),
      ];
    if (sector.isNotEmpty && !_store.business.sectors.contains(sector)) {
      _store.updateBusiness((b) => b.sectors.add(sector));
    }
    _store.upsert(_store.customers, c);
    Navigator.pop(context);
  }

  Widget _section(String title, IconData icon, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 12),
            for (final w in children) ...[w, const SizedBox(height: 12)],
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    String? hint,
    IconData? icon,
    TextInputType? type,
    int lines = 1,
  }) => TextField(
    controller: c,
    keyboardType: type,
    maxLines: lines,
    decoration: InputDecoration(labelText: label, hintText: hint, prefixIcon: icon == null ? null : Icon(icon)),
  );

  Widget _dateTile(String label, DateTime? value, ValueChanged<DateTime?> onChanged, {IconData icon = Icons.event}) =>
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(alignment: AlignmentDirectional.centerStart, padding: const EdgeInsets.all(14)),
        icon: Icon(icon),
        label: Row(
          children: [
            Expanded(child: Text(value == null ? label : '$label: ${Fmt.date(value)}')),
            if (value != null) InkWell(onTap: () => onChanged(null), child: const Icon(Icons.clear, size: 18)),
          ],
        ),
        onPressed: () async {
          final d = await pickDate(context, value ?? DateTime.now(), first: DateTime(1950));
          if (d != null) onChanged(d);
        },
      );

  Widget _pickFromList(TextEditingController c, List<String> options) => options.isEmpty
      ? const SizedBox.shrink()
      : PopupMenuButton<String>(
          icon: const Icon(Icons.arrow_drop_down_circle_outlined),
          tooltip: 'اختر من القائمة',
          itemBuilder: (_) => [for (final o in options) PopupMenuItem(value: o, child: Text(o))],
          onSelected: (v) => setState(() => c.text = v),
        );

  @override
  Widget build(BuildContext context) {
    final store = context.watch<AppStore>();
    final sectors = store.business.sectors;
    final serviceNames = {...store.products.all.where((p) => p.isActive).map((p) => p.name), ..._services}.toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(_c == null ? 'عميل جديد' : 'تعديل بيانات العميل'),
        actions: [TextButton(onPressed: _save, child: const Text('حفظ'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _section('بيانات العميل', Icons.apartment, [
            _field(_name, 'اسم العميل / الجهة *', hint: 'مثال: مستشفى الدمرداش، معمل الخبراء', icon: Icons.business),
            TextField(
              controller: _sector,
              decoration: InputDecoration(
                labelText: 'القطاع / نوع العميل',
                hintText: 'مثال: مستشفى، عيادة أسنان، معمل تحاليل',
                prefixIcon: const Icon(Icons.local_hospital_outlined),
                suffixIcon: _pickFromList(_sector, sectors),
              ),
            ),
            _field(
              _company,
              'الفرع / الجهة التابع لها',
              hint: 'مثال: فرع مدينة نصر',
              icon: Icons.account_tree_outlined,
            ),
            DropdownButtonFormField<CustomerStatus>(
              initialValue: _status,
              decoration: const InputDecoration(labelText: 'حالة التعامل', prefixIcon: Icon(Icons.flag_outlined)),
              items: [for (final s in CustomerStatus.values) DropdownMenuItem(value: s, child: Text(s.label))],
              onChanged: (v) => setState(() => _status = v ?? _status),
            ),
          ]),
          _section('المسؤول والتواصل', Icons.person, [
            _field(_contact, 'اسم المسؤول', hint: 'مثال: د. أحمد محمود', icon: Icons.badge_outlined),
            _field(_contactRole, 'وظيفته', hint: 'مثال: مدير التسويق', icon: Icons.work_outline),
            _field(_phone, 'رقم الهاتف', hint: '01xxxxxxxxx', icon: Icons.phone, type: TextInputType.phone),
            _field(_whatsapp, 'رقم واتساب (لو مختلف)', icon: Icons.chat, type: TextInputType.phone),
            _field(_email, 'البريد الإلكتروني', icon: Icons.email_outlined, type: TextInputType.emailAddress),
            _field(_city, 'المدينة / المنطقة', hint: 'مثال: العباسية، القاهرة', icon: Icons.location_city),
            _field(_address, 'العنوان', icon: Icons.place_outlined),
            _dateTile('عيد ميلاد المسؤول', _birthday, (d) => setState(() => _birthday = d), icon: Icons.cake_outlined),
          ]),
          _section('التعاقد والسعر', Icons.request_quote, [
            SegmentedButton<FeeCycle>(
              segments: const [
                ButtonSegment(value: FeeCycle.monthly, label: Text('شهري')),
                ButtonSegment(value: FeeCycle.oneTime, label: Text('مرة واحدة')),
                ButtonSegment(value: FeeCycle.none, label: Text('بدون')),
              ],
              selected: {_feeCycle},
              onSelectionChanged: (s) => setState(() => _feeCycle = s.first),
            ),
            if (_feeCycle != FeeCycle.none)
              Row(
                children: [
                  Expanded(
                    child: AmountField(
                      label: _feeCycle == FeeCycle.monthly ? 'قيمة الاشتراك الشهري' : 'قيمة التعاقد',
                      value: _fee,
                      suffix: Fmt.symbol,
                      onChanged: (v) => _fee = v,
                    ),
                  ),
                  if (_feeCycle == FeeCycle.monthly) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: _billingDay,
                        decoration: const InputDecoration(labelText: 'بيدفع يوم'),
                        items: [for (var d = 1; d <= 28; d++) DropdownMenuItem(value: d, child: Text(Fmt.number(d)))],
                        onChanged: (v) => setState(() => _billingDay = v ?? 1),
                      ),
                    ),
                  ],
                ],
              ),
            _dateTile('بداية التعاقد', _contractStart, (d) => setState(() => _contractStart = d)),
            _dateTile(
              'نهاية التعاقد (هيجيلك تنبيه قبلها)',
              _contractEnd,
              (d) => setState(() => _contractEnd = d),
              icon: Icons.event_busy,
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('الخدمات المتفق عليها'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final name in serviceNames)
                      FilterChip(
                        label: Text(name),
                        selected: _services.contains(name),
                        onSelected: (v) => setState(() => v ? _services.add(name) : _services.remove(name)),
                      ),
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 16),
                      label: const Text('خدمة أخرى'),
                      onPressed: () async {
                        final v = await promptText(
                          context,
                          'خدمة متفق عليها',
                          hint: 'مثال: إدارة صفحات، حملات إعلانية',
                        );
                        if (v != null && v.isNotEmpty && !_services.contains(v)) setState(() => _services.add(v));
                      },
                    ),
                  ],
                ),
              ],
            ),
          ]),
          _section('خانات إضافية', Icons.dynamic_form, [
            const Text(
              'املاها باللي تحبه. تقدر تضيف خانات تظهر لكل العملاء من المزيد ← تخصيص الخانات.',
              style: TextStyle(fontSize: 12),
            ),
            for (final f in _fields)
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: f.$1,
                      readOnly: f.$3,
                      decoration: const InputDecoration(labelText: 'اسم الخانة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: f.$2,
                      decoration: const InputDecoration(labelText: 'القيمة'),
                    ),
                  ),
                  if (!f.$3)
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      onPressed: () => setState(() => _fields.remove(f)),
                    ),
                ],
              ),
            OutlinedButton.icon(
              onPressed: () => setState(() => _fields.add((TextEditingController(), TextEditingController(), false))),
              icon: const Icon(Icons.add),
              label: const Text('إضافة خانة لهذا العميل'),
            ),
          ]),
          _section('تصنيف وملاحظات', Icons.notes, [
            Row(
              children: [
                const Text('التقييم'),
                const Spacer(),
                for (var i = 1; i <= 5; i++)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    onPressed: () => setState(() => _rating = _rating == i ? 0 : i),
                    icon: Icon(i <= _rating ? Icons.star : Icons.star_border, color: Colors.amber),
                  ),
              ],
            ),
            TextField(
              controller: _source,
              decoration: InputDecoration(
                labelText: 'عرفنا منين',
                hintText: 'مثال: ترشيح، زيارة، فيسبوك',
                suffixIcon: _pickFromList(_source, customerSources),
              ),
            ),
            Wrap(
              spacing: 6,
              children: [
                for (final t in _tags) InputChip(label: Text(t), onDeleted: () => setState(() => _tags.remove(t))),
              ],
            ),
            TextField(
              controller: _tag,
              onSubmitted: (_) => _addTag(),
              decoration: InputDecoration(
                labelText: 'وسوم',
                hintText: 'مثال: مهم، متأخر في الدفع',
                suffixIcon: IconButton(icon: const Icon(Icons.add), onPressed: _addTag),
              ),
            ),
            _field(_notes, 'ملاحظات', hint: 'أي تفاصيل عايز تفتكرها عن العميل', lines: 4),
          ]),
          FilledButton(onPressed: _save, child: const Text('حفظ')),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
