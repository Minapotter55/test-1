import 'dart:math';

import '../models/models.dart';
import 'store.dart';

/// Demo data so a new user (or a client you demo the app to) sees a full dashboard.
void loadSampleData(AppStore store) {
  final rnd = Random(7);
  final now = DateTime.now();
  DateTime daysAgo(int d) => now.subtract(Duration(days: d));
  DateTime daysAhead(int d) => now.add(Duration(days: d));

  final products = [
    Product(name: 'إدارة صفحات السوشيال', price: 4000, cost: 1200, isService: true, category: 'سوشيال ميديا'),
    Product(name: 'حملة إعلانية ممولة', price: 3000, cost: 1500, isService: true, category: 'إعلانات'),
    Product(name: 'تصوير فيديو', price: 2500, cost: 900, isService: true, category: 'إنتاج'),
    Product(name: 'تصميم بوستات', price: 1500, cost: 400, isService: true, category: 'تصميم'),
    Product(name: 'استشارة تسويقية', price: 1000, isService: true, category: 'استشارات'),
  ];
  for (final p in products) {
    store.upsert(store.products, p);
  }

  // Fictional healthcare clients (hospitals, clinics, labs).
  final seeds = [
    ('مستشفى النور التخصصي', 'مستشفى', 'د. أحمد محمود', 'مدير التسويق', CustomerStatus.vip, 'القاهرة', 6000.0),
    (
      'عيادات بسمة لطب الأسنان',
      'عيادة أسنان',
      'د. سارة علي',
      'صاحبة العيادة',
      CustomerStatus.active,
      'مدينة نصر',
      3500.0,
    ),
    ('معمل الحياة للتحاليل', 'معمل تحاليل', 'أ. محمد حسن', 'مدير الفروع', CustomerStatus.active, 'الإسكندرية', 4500.0),
    ('مركز الشفاء للأشعة', 'مركز أشعة', 'د. منى إبراهيم', 'المدير الطبي', CustomerStatus.prospect, 'المنصورة', 0.0),
    ('مستشفى الرحمة', 'مستشفى', 'أ. خالد يوسف', 'مدير العلاقات العامة', CustomerStatus.lead, 'القاهرة', 15000.0),
    ('مركز الأمل الطبي', 'مركز طبي', 'د. ياسمين طارق', 'مديرة المركز', CustomerStatus.active, 'طنطا', 2500.0),
    ('صيدليات الصحة', 'صيدلية', 'د. عمر سمير', 'المالك', CustomerStatus.inactive, 'أسيوط', 0.0),
    ('عيادة د. نورا للجلدية', 'عيادة', 'د. نورا عادل', 'صاحبة العيادة', CustomerStatus.vip, 'الشيخ زايد', 5000.0),
  ];
  final serviceSets = [
    ['إدارة صفحات السوشيال', 'حملة إعلانية ممولة', 'تصوير فيديو'],
    ['إدارة صفحات السوشيال', 'تصميم بوستات'],
    ['حملة إعلانية ممولة'],
    ['استشارة تسويقية'],
    ['تصوير فيديو', 'تصميم بوستات'],
    ['إدارة صفحات السوشيال'],
    <String>[],
    ['إدارة صفحات السوشيال', 'حملة إعلانية ممولة'],
  ];
  final customers = <Customer>[];
  for (var i = 0; i < seeds.length; i++) {
    final s = seeds[i];
    final monthly = s.$5 == CustomerStatus.vip || s.$5 == CustomerStatus.active;
    final c = Customer(
      name: s.$1,
      sector: s.$2,
      contactPerson: s.$3,
      contactRole: s.$4,
      status: s.$5,
      city: s.$6,
      phone: '01${(i % 3)}${(12345678 + i * 1111111).toString().padLeft(8, '0').substring(0, 8)}',
      source: ['ترشيح من عميل', 'زيارة مباشرة', 'فيسبوك', 'إعلان ممول'][i % 4],
      rating: [5, 4, 4, 3, 2, 4, 2, 5][i],
      isFavorite: s.$5 == CustomerStatus.vip,
      createdAt: daysAgo(170 - i * 18),
      lastContactAt: daysAgo(i * 3 + 1),
      birthday: i == 1 ? DateTime(1985, now.month, (now.day % 28) + 1) : null,
      email: 'marketing${i + 1}@example.com',
      services: serviceSets[i],
      feeCycle: s.$7 == 0 ? FeeCycle.none : (monthly ? FeeCycle.monthly : FeeCycle.oneTime),
      fee: s.$7,
      billingDay: 5,
      contractStart: monthly ? daysAgo(170 - i * 18) : null,
      // One contract ends soon so the reminder shows up in the demo.
      contractEnd: monthly ? (i == 1 ? daysAhead(10) : daysAhead(200 - i * 10)) : null,
      customFields: [
        if (monthly) CustomField(key: 'رقم التعاقد', value: 'C-${2026}-${(i + 1).toString().padLeft(3, '0')}'),
        if (i == 0 || i == 2) CustomField(key: 'عدد الفروع', value: i == 0 ? '3' : '12'),
      ],
    );
    store.upsert(store.customers, c);
    customers.add(c);
  }

  const methods = [PaymentMethod.cash, PaymentMethod.instapay, PaymentMethod.bank];
  for (var m = 0; m < 6; m++) {
    for (var j = 0; j < 3; j++) {
      final issue = daysAgo(m * 30 + j * 7 + 2);
      final picks = [products[(m + j) % products.length], products[(m + j + 2) % products.length]];
      final inv = Invoice(
        number: store.takeInvoiceNumber(),
        customerId: customers[(m * 3 + j) % customers.length].id,
        issueDate: issue,
        dueDate: issue.add(const Duration(days: 14)),
        items: [
          for (var k = 0; k < picks.length; k++)
            InvoiceItem(name: picks[k].name, quantity: k + 1.0, unitPrice: picks[k].price, productId: picks[k].id),
        ],
      );
      final total = inv.total;
      final paid = m >= 2 ? total : (j == 0 ? total / 2 : (j == 1 ? 0.0 : total));
      if (paid > 0) {
        inv.payments.add(Payment(amount: paid, date: issue.add(const Duration(days: 3)), method: methods[j]));
      }
      store.upsert(store.invoices, inv);
    }
  }

  final deals = [
    ('تجديد العقد السنوي', 36000.0, DealStage.negotiation, 0),
    ('حملة إعلانية', 15000.0, DealStage.proposal, 2),
    ('تصميم منيو جديد', 7500.0, DealStage.contacted, 2),
    ('باقة سوشيال ميديا', 9000.0, DealStage.newDeal, 3),
    ('موقع إلكتروني', 25000.0, DealStage.proposal, 4),
    ('توريد منتجات', 12000.0, DealStage.won, 5),
    ('إدارة صفحات', 6000.0, DealStage.lost, 6),
    ('برنامج ولاء العملاء', 18000.0, DealStage.won, 7),
  ];
  for (final d in deals) {
    store.upsert(
      store.deals,
      Deal(
        title: d.$1,
        value: d.$2,
        stage: d.$3,
        customerId: customers[d.$4].id,
        expectedClose: daysAhead(5 + rnd.nextInt(35)),
        createdAt: daysAgo(5 + rnd.nextInt(55)),
        closedAt: d.$3.isOpen ? null : daysAgo(1 + rnd.nextInt(20)),
      ),
    );
  }

  final tasks = [
    ('متابعة عرض السعر', 0, TaskPriority.high, 1, RepeatRule.none),
    ('إرسال الفاتورة المتأخرة', -2, TaskPriority.high, 0, RepeatRule.none),
    ('مكالمة ترحيب بالعميل الجديد', 1, TaskPriority.medium, 4, RepeatRule.none),
    ('تحضير عرض تقديمي', 3, TaskPriority.medium, 3, RepeatRule.none),
    ('متابعة شهرية مع العميل', 5, TaskPriority.low, 5, RepeatRule.monthly),
    ('مراجعة المصروفات', 7, TaskPriority.low, -1, RepeatRule.weekly),
  ];
  for (final t in tasks) {
    final day = daysAhead(t.$2);
    store.upsert(
      store.tasks,
      TaskItem(
        title: t.$1,
        dueDate: DateTime(day.year, day.month, day.day, 11),
        priority: t.$3,
        customerId: t.$4 >= 0 ? customers[t.$4].id : null,
        repeat: t.$5,
      ),
    );
  }

  final logs = [
    (InteractionType.call, 'اتصل يسأل عن الأسعار الجديدة', 0, 1),
    (InteractionType.whatsapp, 'أرسلت له عرض السعر على واتساب', 1, 2),
    (InteractionType.meeting, 'اجتماع لمناقشة الخطة الشهرية', 0, 6),
    (InteractionType.visit, 'زيارة للمقر وتسليم الطلبية', 2, 9),
    (InteractionType.note, 'يفضل التواصل بعد الساعة 5 مساءً', 3, 12),
  ];
  for (final l in logs) {
    store.upsert(
      store.interactions,
      Interaction(customerId: customers[l.$3].id, type: l.$1, summary: l.$2, date: daysAgo(l.$4)),
    );
  }

  for (var m = 0; m < 6; m++) {
    final start = DateTime(now.year, now.month - m);
    final items = [
      ('إيجار المكتب', 4000.0, ExpenseCategory.rent, 1),
      ('رواتب', 9000.0, ExpenseCategory.salaries, 25),
      ('إعلانات فيسبوك', 1500.0 + m * 200, ExpenseCategory.marketing, 10),
      ('إنترنت وكهرباء', 650.0, ExpenseCategory.utilities, 5),
    ];
    for (final e in items) {
      final date = DateTime(start.year, start.month, e.$4);
      if (date.isAfter(now)) continue;
      store.upsert(store.expenses, Expense(title: e.$1, amount: e.$2, category: e.$3, date: date));
    }
    // Money spent on specific clients (ads budget, freelancers).
    final clientCosts = [
      ('ميزانية إعلانات ممولة', 1200.0 + m * 100, ExpenseCategory.marketing, 0),
      ('مصمم فريلانس', 900.0, ExpenseCategory.salaries, 2),
      ('مصور فيديو', 700.0, ExpenseCategory.supplies, 7),
    ];
    for (final e in clientCosts) {
      final date = DateTime(start.year, start.month, 12);
      if (date.isAfter(now)) continue;
      store.upsert(
        store.expenses,
        Expense(title: e.$1, amount: e.$2, category: e.$3, date: date, customerId: customers[e.$4].id),
      );
    }
  }
}
