import 'package:uuid/uuid.dart';

import 'enums.dart';

export 'enums.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

DateTime? _date(Object? v) => v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
int? _ms(DateTime? d) => d?.millisecondsSinceEpoch;
double _double(Object? v) => v is num ? v.toDouble() : 0;
int _int(Object? v) => v is num ? v.toInt() : 0;
String _str(Object? v) => v is String ? v : '';

/// Every stored record has an id and a last-modified timestamp; sync merges on these.
abstract class Entity {
  Entity({String? id, int? updatedAt})
    : id = id ?? newId(),
      updatedAt = updatedAt ?? DateTime.now().millisecondsSinceEpoch;

  final String id;
  int updatedAt;

  Map<String, dynamic> toJson();

  void touch() => updatedAt = DateTime.now().millisecondsSinceEpoch;
}

class CustomField {
  CustomField({this.key = '', this.value = ''});
  String key;
  String value;

  Map<String, dynamic> toJson() => {'k': key, 'v': value};
  factory CustomField.fromJson(Map<String, dynamic> j) => CustomField(key: _str(j['k']), value: _str(j['v']));
}

class Customer extends Entity {
  Customer({
    super.id,
    super.updatedAt,
    this.name = '',
    this.company = '',
    this.phone = '',
    this.whatsapp = '',
    this.email = '',
    this.city = '',
    this.address = '',
    this.notes = '',
    this.source = '',
    List<String>? tags,
    this.status = CustomerStatus.lead,
    this.rating = 0,
    this.isFavorite = false,
    DateTime? createdAt,
    this.lastContactAt,
    this.birthday,
    List<CustomField>? customFields,
  }) : tags = tags ?? [],
       customFields = customFields ?? [],
       createdAt = createdAt ?? DateTime.now();

  String name, company, phone, whatsapp, email, city, address, notes, source;
  List<String> tags;
  CustomerStatus status;
  int rating;
  bool isFavorite;
  DateTime createdAt;
  DateTime? lastContactAt;
  DateTime? birthday;
  List<CustomField> customFields;

  String get whatsappNumber => whatsapp.isEmpty ? phone : whatsapp;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'name': name,
    'company': company,
    'phone': phone,
    'whatsapp': whatsapp,
    'email': email,
    'city': city,
    'address': address,
    'notes': notes,
    'source': source,
    'tags': tags,
    'status': status.name,
    'rating': rating,
    'fav': isFavorite,
    'created': _ms(createdAt),
    'lastContact': _ms(lastContactAt),
    'birthday': _ms(birthday),
    'fields': customFields.map((f) => f.toJson()).toList(),
  };

  factory Customer.fromJson(Map<String, dynamic> j) => Customer(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    name: _str(j['name']),
    company: _str(j['company']),
    phone: _str(j['phone']),
    whatsapp: _str(j['whatsapp']),
    email: _str(j['email']),
    city: _str(j['city']),
    address: _str(j['address']),
    notes: _str(j['notes']),
    source: _str(j['source']),
    tags: (j['tags'] as List?)?.whereType<String>().toList(),
    status: enumByName(CustomerStatus.values, j['status'], CustomerStatus.lead),
    rating: _int(j['rating']),
    isFavorite: j['fav'] == true,
    createdAt: _date(j['created']),
    lastContactAt: _date(j['lastContact']),
    birthday: _date(j['birthday']),
    customFields: (j['fields'] as List?)
        ?.whereType<Map>()
        .map((m) => CustomField.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
  );
}

class Deal extends Entity {
  Deal({
    super.id,
    super.updatedAt,
    this.title = '',
    this.value = 0,
    this.stage = DealStage.newDeal,
    int? probability,
    this.customerId,
    this.expectedClose,
    this.notes = '',
    DateTime? createdAt,
    this.closedAt,
  }) : probability = probability ?? stage.defaultProbability,
       createdAt = createdAt ?? DateTime.now();

  String title;
  double value;
  DealStage stage;
  int probability;
  String? customerId;
  DateTime? expectedClose;
  String notes;
  DateTime createdAt;
  DateTime? closedAt;

  double get weightedValue => value * probability / 100;

  void moveTo(DealStage newStage) {
    stage = newStage;
    probability = newStage.defaultProbability;
    closedAt = newStage.isOpen ? null : (closedAt ?? DateTime.now());
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'title': title,
    'value': value,
    'stage': stage.name,
    'prob': probability,
    'customer': customerId,
    'close': _ms(expectedClose),
    'notes': notes,
    'created': _ms(createdAt),
    'closed': _ms(closedAt),
  };

  factory Deal.fromJson(Map<String, dynamic> j) => Deal(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    title: _str(j['title']),
    value: _double(j['value']),
    stage: enumByName(DealStage.values, j['stage'], DealStage.newDeal),
    probability: j['prob'] is num ? _int(j['prob']) : null,
    customerId: j['customer'] as String?,
    expectedClose: _date(j['close']),
    notes: _str(j['notes']),
    createdAt: _date(j['created']),
    closedAt: _date(j['closed']),
  );
}

class InvoiceItem {
  InvoiceItem({this.name = '', this.quantity = 1, this.unitPrice = 0, this.productId});
  String name;
  double quantity;
  double unitPrice;
  String? productId;

  double get total => quantity * unitPrice;

  Map<String, dynamic> toJson() => {'n': name, 'q': quantity, 'p': unitPrice, 'pid': productId};
  factory InvoiceItem.fromJson(Map<String, dynamic> j) => InvoiceItem(
    name: _str(j['n']),
    quantity: _double(j['q']),
    unitPrice: _double(j['p']),
    productId: j['pid'] as String?,
  );
}

class Payment {
  Payment({String? id, this.amount = 0, DateTime? date, this.method = PaymentMethod.cash, this.note = ''})
    : id = id ?? newId(),
      date = date ?? DateTime.now();
  final String id;
  double amount;
  DateTime date;
  PaymentMethod method;
  String note;

  Map<String, dynamic> toJson() => {'id': id, 'a': amount, 'd': _ms(date), 'm': method.name, 'note': note};
  factory Payment.fromJson(Map<String, dynamic> j) => Payment(
    id: j['id'] as String?,
    amount: _double(j['a']),
    date: _date(j['d']),
    method: enumByName(PaymentMethod.values, j['m'], PaymentMethod.cash),
    note: _str(j['note']),
  );
}

class Invoice extends Entity {
  Invoice({
    super.id,
    super.updatedAt,
    this.number = '',
    this.customerId,
    DateTime? issueDate,
    DateTime? dueDate,
    this.state = InvoiceState.issued,
    this.discount = 0,
    this.taxRate = 0,
    this.notes = '',
    List<InvoiceItem>? items,
    List<Payment>? payments,
    DateTime? createdAt,
  }) : issueDate = issueDate ?? DateTime.now(),
       dueDate = dueDate ?? DateTime.now(),
       items = items ?? [],
       payments = payments ?? [],
       createdAt = createdAt ?? DateTime.now();

  String number;
  String? customerId;
  DateTime issueDate;
  DateTime dueDate;
  InvoiceState state;
  double discount;
  double taxRate;
  String notes;
  List<InvoiceItem> items;
  List<Payment> payments;
  DateTime createdAt;

  double get subtotal => items.fold(0, (s, i) => s + i.total);
  double get taxable => (subtotal - discount).clamp(0, double.infinity).toDouble();
  double get taxAmount => taxable * taxRate / 100;
  double get total => taxable + taxAmount;
  double get paidAmount => payments.fold(0, (s, p) => s + p.amount);
  double get balance => (total - paidAmount).clamp(0, double.infinity).toDouble();

  InvoiceStatus get status {
    switch (state) {
      case InvoiceState.draft:
        return InvoiceStatus.draft;
      case InvoiceState.cancelled:
        return InvoiceStatus.cancelled;
      case InvoiceState.issued:
        if (balance <= 0.009) return InvoiceStatus.paid;
        final now = DateTime.now();
        if (dueDate.isBefore(DateTime(now.year, now.month, now.day))) return InvoiceStatus.overdue;
        if (paidAmount > 0) return InvoiceStatus.partial;
        return InvoiceStatus.unpaid;
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'number': number,
    'customer': customerId,
    'issue': _ms(issueDate),
    'due': _ms(dueDate),
    'state': state.name,
    'discount': discount,
    'tax': taxRate,
    'notes': notes,
    'items': items.map((i) => i.toJson()).toList(),
    'payments': payments.map((p) => p.toJson()).toList(),
    'created': _ms(createdAt),
  };

  factory Invoice.fromJson(Map<String, dynamic> j) => Invoice(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    number: _str(j['number']),
    customerId: j['customer'] as String?,
    issueDate: _date(j['issue']),
    dueDate: _date(j['due']),
    state: enumByName(InvoiceState.values, j['state'], InvoiceState.issued),
    discount: _double(j['discount']),
    taxRate: _double(j['tax']),
    notes: _str(j['notes']),
    items: (j['items'] as List?)
        ?.whereType<Map>()
        .map((m) => InvoiceItem.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    payments: (j['payments'] as List?)
        ?.whereType<Map>()
        .map((m) => Payment.fromJson(Map<String, dynamic>.from(m)))
        .toList(),
    createdAt: _date(j['created']),
  );
}

class Product extends Entity {
  Product({
    super.id,
    super.updatedAt,
    this.name = '',
    this.sku = '',
    this.category = '',
    this.price = 0,
    this.cost = 0,
    this.stock = 0,
    this.trackStock = false,
    this.lowStockThreshold = 5,
    this.isService = false,
    this.isActive = true,
    this.notes = '',
  });

  String name, sku, category, notes;
  double price, cost;
  int stock, lowStockThreshold;
  bool trackStock, isService, isActive;

  bool get isLowStock => trackStock && stock <= lowStockThreshold;
  double get marginPercent => price > 0 ? (price - cost) / price * 100 : 0;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'name': name,
    'sku': sku,
    'category': category,
    'price': price,
    'cost': cost,
    'stock': stock,
    'track': trackStock,
    'low': lowStockThreshold,
    'service': isService,
    'active': isActive,
    'notes': notes,
  };

  factory Product.fromJson(Map<String, dynamic> j) => Product(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    name: _str(j['name']),
    sku: _str(j['sku']),
    category: _str(j['category']),
    price: _double(j['price']),
    cost: _double(j['cost']),
    stock: _int(j['stock']),
    trackStock: j['track'] == true,
    lowStockThreshold: j['low'] is num ? _int(j['low']) : 5,
    isService: j['service'] == true,
    isActive: j['active'] != false,
    notes: _str(j['notes']),
  );
}

class TaskItem extends Entity {
  TaskItem({
    super.id,
    super.updatedAt,
    this.title = '',
    this.notes = '',
    this.dueDate,
    this.isDone = false,
    this.completedAt,
    this.priority = TaskPriority.medium,
    this.reminder = true,
    this.repeat = RepeatRule.none,
    this.customerId,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  String title, notes;
  DateTime? dueDate;
  bool isDone;
  DateTime? completedAt;
  TaskPriority priority;
  bool reminder;
  RepeatRule repeat;
  String? customerId;
  DateTime createdAt;

  bool get isOverdue => !isDone && dueDate != null && dueDate!.isBefore(DateTime.now());
  bool get isDueToday {
    final d = dueDate;
    if (d == null) return false;
    final n = DateTime.now();
    return d.year == n.year && d.month == n.month && d.day == n.day;
  }

  /// Marks done; a repeating task instead moves to its next occurrence.
  void complete() {
    final d = dueDate;
    if (repeat != RepeatRule.none && d != null) {
      var next = nextOccurrence(d, repeat);
      final now = DateTime.now();
      while (!next.isAfter(now)) {
        next = nextOccurrence(next, repeat);
      }
      dueDate = next;
    } else {
      isDone = true;
      completedAt = DateTime.now();
    }
  }

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'title': title,
    'notes': notes,
    'due': _ms(dueDate),
    'done': isDone,
    'completed': _ms(completedAt),
    'priority': priority.name,
    'reminder': reminder,
    'repeat': repeat.name,
    'customer': customerId,
    'created': _ms(createdAt),
  };

  factory TaskItem.fromJson(Map<String, dynamic> j) => TaskItem(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    title: _str(j['title']),
    notes: _str(j['notes']),
    dueDate: _date(j['due']),
    isDone: j['done'] == true,
    completedAt: _date(j['completed']),
    priority: enumByName(TaskPriority.values, j['priority'], TaskPriority.medium),
    reminder: j['reminder'] != false,
    repeat: enumByName(RepeatRule.values, j['repeat'], RepeatRule.none),
    customerId: j['customer'] as String?,
    createdAt: _date(j['created']),
  );
}

DateTime nextOccurrence(DateTime d, RepeatRule rule) {
  switch (rule) {
    case RepeatRule.none:
      return d;
    case RepeatRule.daily:
      return DateTime(d.year, d.month, d.day + 1, d.hour, d.minute);
    case RepeatRule.weekly:
      return DateTime(d.year, d.month, d.day + 7, d.hour, d.minute);
    case RepeatRule.monthly:
      return DateTime(d.year, d.month + 1, d.day, d.hour, d.minute);
    case RepeatRule.yearly:
      return DateTime(d.year + 1, d.month, d.day, d.hour, d.minute);
  }
}

class Interaction extends Entity {
  Interaction({
    super.id,
    super.updatedAt,
    required this.customerId,
    this.type = InteractionType.note,
    this.summary = '',
    DateTime? date,
  }) : date = date ?? DateTime.now();

  String customerId;
  InteractionType type;
  String summary;
  DateTime date;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'customer': customerId,
    'type': type.name,
    'summary': summary,
    'date': _ms(date),
  };

  factory Interaction.fromJson(Map<String, dynamic> j) => Interaction(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    customerId: _str(j['customer']),
    type: enumByName(InteractionType.values, j['type'], InteractionType.note),
    summary: _str(j['summary']),
    date: _date(j['date']),
  );
}

class Expense extends Entity {
  Expense({
    super.id,
    super.updatedAt,
    this.title = '',
    this.amount = 0,
    DateTime? date,
    this.category = ExpenseCategory.other,
    this.notes = '',
  }) : date = date ?? DateTime.now();

  String title;
  double amount;
  DateTime date;
  ExpenseCategory category;
  String notes;

  @override
  Map<String, dynamic> toJson() => {
    'id': id,
    'u': updatedAt,
    'title': title,
    'amount': amount,
    'date': _ms(date),
    'category': category.name,
    'notes': notes,
  };

  factory Expense.fromJson(Map<String, dynamic> j) => Expense(
    id: j['id'] as String?,
    updatedAt: j['u'] as int?,
    title: _str(j['title']),
    amount: _double(j['amount']),
    date: _date(j['date']),
    category: enumByName(ExpenseCategory.values, j['category'], ExpenseCategory.other),
    notes: _str(j['notes']),
  );
}

/// Business profile — synced across devices together with the data.
class BusinessSettings {
  BusinessSettings({
    this.name = '',
    this.phone = '',
    this.email = '',
    this.address = '',
    this.taxId = '',
    this.logoBase64 = '',
    this.currency = 'EGP',
    this.countryCode = '20',
    this.invoicePrefix = 'INV-',
    this.nextInvoiceNumber = 1,
    this.defaultTaxRate = 0,
    this.defaultDueDays = 14,
    this.invoiceFooter = 'شكراً لتعاملكم معنا',
    this.monthlyTarget = 0,
    int? updatedAt,
  }) : updatedAt = updatedAt ?? 0;

  String name, phone, email, address, taxId, logoBase64, currency, countryCode, invoicePrefix, invoiceFooter;
  int nextInvoiceNumber, defaultDueDays;
  double defaultTaxRate, monthlyTarget;
  int updatedAt;

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'email': email,
    'address': address,
    'taxId': taxId,
    'logo': logoBase64,
    'currency': currency,
    'country': countryCode,
    'prefix': invoicePrefix,
    'next': nextInvoiceNumber,
    'tax': defaultTaxRate,
    'dueDays': defaultDueDays,
    'footer': invoiceFooter,
    'target': monthlyTarget,
    'u': updatedAt,
  };

  factory BusinessSettings.fromJson(Map<String, dynamic> j) => BusinessSettings(
    name: _str(j['name']),
    phone: _str(j['phone']),
    email: _str(j['email']),
    address: _str(j['address']),
    taxId: _str(j['taxId']),
    logoBase64: _str(j['logo']),
    currency: j['currency'] is String ? j['currency'] as String : 'EGP',
    countryCode: j['country'] is String ? j['country'] as String : '20',
    invoicePrefix: j['prefix'] is String ? j['prefix'] as String : 'INV-',
    nextInvoiceNumber: j['next'] is num ? _int(j['next']) : 1,
    defaultTaxRate: _double(j['tax']),
    defaultDueDays: j['dueDays'] is num ? _int(j['dueDays']) : 14,
    invoiceFooter: j['footer'] is String ? j['footer'] as String : '',
    monthlyTarget: _double(j['target']),
    updatedAt: j['u'] as int?,
  );
}
