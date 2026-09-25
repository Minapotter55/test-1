import 'package:flutter/material.dart';

T enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

enum CustomerStatus {
  lead('عميل محتمل', Colors.blue, Icons.person_search),
  prospect('مهتم', Colors.orange, Icons.auto_awesome),
  active('نشط', Colors.green, Icons.verified),
  vip('VIP', Colors.purple, Icons.workspace_premium),
  inactive('غير نشط', Colors.grey, Icons.bedtime);

  const CustomerStatus(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;
}

enum DealStage {
  newDeal('جديدة', Colors.blue, Icons.fiber_new, 10),
  contacted('تم التواصل', Colors.teal, Icons.call, 25),
  proposal('عرض سعر', Colors.orange, Icons.request_quote, 50),
  negotiation('تفاوض', Colors.purple, Icons.handshake, 75),
  won('مكسب', Colors.green, Icons.emoji_events, 100),
  lost('خسارة', Colors.red, Icons.cancel, 0);

  const DealStage(this.label, this.color, this.icon, this.defaultProbability);
  final String label;
  final Color color;
  final IconData icon;
  final int defaultProbability;

  bool get isOpen => this != won && this != lost;
  static List<DealStage> get openStages => values.where((s) => s.isOpen).toList();
}

/// What the user explicitly set on an invoice.
enum InvoiceState { draft, issued, cancelled }

/// What the invoice looks like now (derived from state, payments and due date).
enum InvoiceStatus {
  draft('مسودة', Colors.grey, Icons.edit_note),
  unpaid('غير مدفوعة', Colors.orange, Icons.schedule),
  partial('مدفوعة جزئياً', Colors.amber, Icons.timelapse),
  overdue('متأخرة', Colors.red, Icons.warning_amber_rounded),
  paid('مدفوعة', Colors.green, Icons.check_circle),
  cancelled('ملغاة', Colors.blueGrey, Icons.block);

  const InvoiceStatus(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final IconData icon;

  bool get isOutstanding => this == unpaid || this == partial || this == overdue;
}

enum PaymentMethod {
  cash('نقدي', Icons.payments),
  bank('تحويل بنكي', Icons.account_balance),
  card('بطاقة', Icons.credit_card),
  wallet('محفظة إلكترونية', Icons.phone_iphone),
  instapay('InstaPay', Icons.bolt),
  cheque('شيك', Icons.receipt_long);

  const PaymentMethod(this.label, this.icon);
  final String label;
  final IconData icon;
}

enum TaskPriority {
  low('منخفضة', Colors.grey),
  medium('متوسطة', Colors.orange),
  high('عالية', Colors.red);

  const TaskPriority(this.label, this.color);
  final String label;
  final Color color;
}

enum RepeatRule {
  none('بدون تكرار'),
  daily('يومياً'),
  weekly('أسبوعياً'),
  monthly('شهرياً'),
  yearly('سنوياً');

  const RepeatRule(this.label);
  final String label;
}

enum InteractionType {
  call('مكالمة', Icons.call, Colors.blue),
  whatsapp('واتساب', Icons.chat, Colors.green),
  meeting('اجتماع', Icons.groups, Colors.purple),
  email('بريد', Icons.email, Colors.orange),
  visit('زيارة', Icons.directions_car, Colors.teal),
  note('ملاحظة', Icons.sticky_note_2, Colors.grey);

  const InteractionType(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

enum ExpenseCategory {
  rent('إيجار', Icons.home_work, Colors.brown),
  salaries('رواتب', Icons.groups, Colors.blue),
  marketing('تسويق وإعلانات', Icons.campaign, Colors.pink),
  supplies('مستلزمات', Icons.inventory_2, Colors.orange),
  transport('مواصلات', Icons.local_shipping, Colors.teal),
  utilities('كهرباء ومياه وإنترنت', Icons.bolt, Colors.amber),
  software('برامج واشتراكات', Icons.apps, Colors.indigo),
  other('أخرى', Icons.more_horiz, Colors.grey);

  const ExpenseCategory(this.label, this.icon, this.color);
  final String label;
  final IconData icon;
  final Color color;
}

const customerSources = [
  'فيسبوك',
  'إنستجرام',
  'تيك توك',
  'واتساب',
  'ترشيح من عميل',
  'الموقع',
  'زيارة مباشرة',
  'إعلان ممول',
];
