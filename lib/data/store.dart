import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/models.dart';

/// A typed set of records keyed by id.
class Collection<T extends Entity> {
  Collection(this.key, this.fromJson);

  final String key;
  final T Function(Map<String, dynamic>) fromJson;
  final Map<String, T> items = {};

  List<T> get all => items.values.toList();

  List<Map<String, dynamic>> toJson() => items.values.map((e) => e.toJson()).toList();

  void load(Object? json) {
    items.clear();
    if (json is! List) return;
    for (final m in json.whereType<Map>()) {
      final e = fromJson(Map<String, dynamic>.from(m));
      items[e.id] = e;
    }
  }

  /// Last-writer-wins per record; tombstones beat older edits.
  bool merge(Object? json, Map<String, int> tombstones) {
    var changed = false;
    if (json is List) {
      for (final m in json.whereType<Map>()) {
        final remote = fromJson(Map<String, dynamic>.from(m));
        final deletedAt = tombstones[remote.id];
        if (deletedAt != null && deletedAt >= remote.updatedAt) continue;
        final local = items[remote.id];
        if (local == null || remote.updatedAt > local.updatedAt) {
          items[remote.id] = remote;
          changed = true;
        }
      }
    }
    tombstones.forEach((id, deletedAt) {
      final local = items[id];
      if (local != null && deletedAt >= local.updatedAt) {
        items.remove(id);
        changed = true;
      }
    });
    return changed;
  }
}

/// All app data, kept in memory and persisted as one JSON file.
/// The same JSON is what gets synced to Google Drive and backed up.
class AppStore extends ChangeNotifier {
  AppStore({this.persist = true});

  /// Tests run without a file system.
  final bool persist;

  static const schemaVersion = 1;
  static const fileName = 'clientpro_data.json';

  final customers = Collection<Customer>('customers', Customer.fromJson);
  final deals = Collection<Deal>('deals', Deal.fromJson);
  final invoices = Collection<Invoice>('invoices', Invoice.fromJson);
  final products = Collection<Product>('products', Product.fromJson);
  final tasks = Collection<TaskItem>('tasks', TaskItem.fromJson);
  final interactions = Collection<Interaction>('interactions', Interaction.fromJson);
  final expenses = Collection<Expense>('expenses', Expense.fromJson);

  late final List<Collection> _collections = [customers, deals, invoices, products, tasks, interactions, expenses];

  BusinessSettings business = BusinessSettings();
  final Map<String, int> tombstones = {};

  /// Bumped on every local edit (not on merges); sync uses it to know when to push.
  int revision = 0;
  bool loaded = false;

  Timer? _saveTimer;
  File? _file;

  // MARK: Persistence

  Future<void> load() async {
    if (persist) {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      _file = File('${dir.path}/$fileName');
      if (await _file!.exists()) {
        try {
          final json = jsonDecode(await _file!.readAsString());
          if (json is Map<String, dynamic>) _apply(json);
        } catch (e) {
          debugPrint('Failed to read data file: $e');
          // Keep a copy of the unreadable file instead of overwriting it.
          await _file!.copy('${_file!.path}.corrupt-${DateTime.now().millisecondsSinceEpoch}');
        }
      }
    }
    loaded = true;
    notifyListeners();
  }

  Map<String, dynamic> snapshot() => {
    'app': 'ClientPro',
    'version': schemaVersion,
    'exportedAt': DateTime.now().millisecondsSinceEpoch,
    'business': business.toJson(),
    'tombstones': tombstones,
    for (final c in _collections) c.key: c.toJson(),
  };

  void _apply(Map<String, dynamic> json) {
    business = json['business'] is Map
        ? BusinessSettings.fromJson(Map<String, dynamic>.from(json['business'] as Map))
        : BusinessSettings();
    tombstones
      ..clear()
      ..addAll(_tombstones(json['tombstones']));
    for (final c in _collections) {
      c.load(json[c.key]);
    }
  }

  static Map<String, int> _tombstones(Object? json) {
    if (json is! Map) return {};
    return {
      for (final e in json.entries)
        if (e.key is String && e.value is num) e.key as String: (e.value as num).toInt(),
    };
  }

  static bool isValidSnapshot(Object? json) => json is Map && json['app'] == 'ClientPro';

  /// Replaces everything (restore from a backup file).
  void replaceWith(Map<String, dynamic> json) {
    _apply(json);
    revision++;
    _changed();
  }

  /// Merges data coming from another device. Returns true if anything changed locally.
  bool mergeFrom(Map<String, dynamic> json) {
    var changed = false;
    final remoteTombstones = _tombstones(json['tombstones']);
    remoteTombstones.forEach((id, t) {
      if ((tombstones[id] ?? 0) < t) tombstones[id] = t;
    });
    for (final c in _collections) {
      if (c.merge(json[c.key], tombstones)) changed = true;
    }
    if (json['business'] is Map) {
      final remote = BusinessSettings.fromJson(Map<String, dynamic>.from(json['business'] as Map));
      if (remote.updatedAt > business.updatedAt) {
        // Never go backwards on invoice numbering.
        remote.nextInvoiceNumber = remote.nextInvoiceNumber > business.nextInvoiceNumber
            ? remote.nextInvoiceNumber
            : business.nextInvoiceNumber;
        business = remote;
        changed = true;
      } else if (remote.nextInvoiceNumber > business.nextInvoiceNumber) {
        business.nextInvoiceNumber = remote.nextInvoiceNumber;
        changed = true;
      }
    }
    if (changed) {
      notifyListeners();
      _scheduleSave();
    }
    return changed;
  }

  void _changed() {
    notifyListeners();
    _scheduleSave();
  }

  void _scheduleSave() {
    if (!persist) return;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), saveNow);
  }

  Future<void> saveNow() async {
    _saveTimer?.cancel();
    final file = _file;
    if (file == null) return;
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(jsonEncode(snapshot()), flush: true);
    await tmp.rename(file.path);
  }

  // MARK: Generic edits

  void upsert<T extends Entity>(Collection<T> c, T item) {
    item.touch();
    c.items[item.id] = item;
    tombstones.remove(item.id);
    revision++;
    _changed();
  }

  void delete<T extends Entity>(Collection<T> c, String id) {
    if (c.items.remove(id) == null) return;
    tombstones[id] = DateTime.now().millisecondsSinceEpoch;
    revision++;
    _changed();
  }

  void updateBusiness(void Function(BusinessSettings b) edit) {
    edit(business);
    business.updatedAt = DateTime.now().millisecondsSinceEpoch;
    revision++;
    _changed();
  }

  void wipe() {
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final c in _collections) {
      for (final id in c.items.keys) {
        tombstones[id] = now;
      }
      c.items.clear();
    }
    revision++;
    _changed();
  }

  // MARK: Domain helpers

  Customer? customer(String? id) => id == null ? null : customers.items[id];

  List<Invoice> invoicesOf(String customerId) =>
      invoices.all.where((i) => i.customerId == customerId).toList()
        ..sort((a, b) => b.issueDate.compareTo(a.issueDate));

  List<Deal> dealsOf(String customerId) => deals.all.where((d) => d.customerId == customerId).toList();

  List<TaskItem> tasksOf(String customerId) => tasks.all.where((t) => t.customerId == customerId).toList();

  List<Interaction> interactionsOf(String customerId) =>
      interactions.all.where((i) => i.customerId == customerId).toList()..sort((a, b) => b.date.compareTo(a.date));

  double totalPaidBy(String customerId) =>
      invoicesOf(customerId).where((i) => i.state == InvoiceState.issued).fold(0.0, (s, i) => s + i.paidAmount);

  double totalInvoicedTo(String customerId) =>
      invoicesOf(customerId).where((i) => i.state == InvoiceState.issued).fold(0.0, (s, i) => s + i.total);

  double balanceOf(String customerId) =>
      invoicesOf(customerId).where((i) => i.status.isOutstanding).fold(0.0, (s, i) => s + i.balance);

  /// Every payment with its invoice, newest first.
  List<(Payment, Invoice)> get allPayments {
    final list = <(Payment, Invoice)>[
      for (final inv in invoices.all)
        if (inv.state != InvoiceState.cancelled)
          for (final p in inv.payments) (p, inv),
    ];
    list.sort((a, b) => b.$1.date.compareTo(a.$1.date));
    return list;
  }

  String peekInvoiceNumber() => '${business.invoicePrefix}${business.nextInvoiceNumber.toString().padLeft(4, '0')}';

  /// Returns the next number and advances the counter.
  String takeInvoiceNumber() {
    final number = peekInvoiceNumber();
    updateBusiness((b) => b.nextInvoiceNumber += 1);
    return number;
  }

  void logInteraction(Customer c, InteractionType type, String summary, {DateTime? date}) {
    final when = date ?? DateTime.now();
    upsert(interactions, Interaction(customerId: c.id, type: type, summary: summary, date: when));
    if (c.lastContactAt == null || c.lastContactAt!.isBefore(when)) {
      c.lastContactAt = when;
      upsert(customers, c);
    }
  }

  void deleteCustomer(Customer c) {
    for (final i in invoicesOf(c.id)) {
      delete(invoices, i.id);
    }
    for (final d in dealsOf(c.id)) {
      delete(deals, d.id);
    }
    for (final i in interactionsOf(c.id)) {
      delete(interactions, i.id);
    }
    for (final t in tasksOf(c.id)) {
      t.customerId = null;
      upsert(tasks, t);
    }
    delete(customers, c.id);
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    super.dispose();
  }
}
