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
    Product(name: 'استشارة', price: 500, isService: true, category: 'خدمات'),
    Product(name: 'باقة شهرية', price: 3000, cost: 800, isService: true, category: 'خدمات'),
    Product(name: 'تصميم هوية بصرية', price: 7500, cost: 1500, isService: true, category: 'تصميم'),
    Product(name: 'منتج أساسي', price: 250, cost: 120, trackStock: true, stock: 40, category: 'منتجات'),
    Product(name: 'منتج مميز', price: 900, cost: 450, trackStock: true, stock: 3, category: 'منتجات'),
  ];
  for (final p in products) {
    store.upsert(store.products, p);
  }

  final seeds = [
    ('أحمد محمود', '01001234567', 'شركة النور للتجارة', CustomerStatus.vip, 'القاهرة', 'ترشيح من عميل'),
    ('سارة علي', '01112345678', '', CustomerStatus.active, 'الجيزة', 'إنستجرام'),
    ('محمد حسن', '01223456789', 'مطعم الشرق', CustomerStatus.active, 'الإسكندرية', 'فيسبوك'),
    ('منى إبراهيم', '01534567890', 'عيادة د. منى', CustomerStatus.prospect, 'المنصورة', 'إعلان ممول'),
    ('خالد يوسف', '01045678901', 'معرض يوسف للسيارات', CustomerStatus.lead, 'القاهرة', 'الموقع'),
    ('ياسمين طارق', '01156789012', '', CustomerStatus.active, 'طنطا', 'تيك توك'),
    ('عمر سمير', '01267890123', 'صيدلية الشفاء', CustomerStatus.inactive, 'أسيوط', 'زيارة مباشرة'),
    ('نورا عادل', '01078901234', 'أكاديمية نورا', CustomerStatus.vip, 'القاهرة', 'ترشيح من عميل'),
  ];
  final customers = <Customer>[];
  for (var i = 0; i < seeds.length; i++) {
    final s = seeds[i];
    final c = Customer(
      name: s.$1,
      phone: s.$2,
      company: s.$3,
      status: s.$4,
      city: s.$5,
      source: s.$6,
      rating: [5, 4, 4, 3, 2, 4, 2, 5][i],
      isFavorite: s.$4 == CustomerStatus.vip,
      tags: [i.isEven ? 'جملة' : 'تجزئة'],
      createdAt: daysAgo(170 - i * 18),
      lastContactAt: daysAgo(i * 3 + 1),
      birthday: i == 1 ? DateTime(1995, now.month, (now.day % 28) + 1) : null,
      email: 'client${i + 1}@example.com',
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
  }
}
