import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../data/prefs.dart';
import '../data/store.dart';
import '../models/models.dart';
import 'format.dart';

/// Monthly Excel reports, full JSON backups and restores.
class Exporter {
  Exporter(this.store);
  final AppStore store;

  static Future<Directory> exportsDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/exports');
    await dir.create(recursive: true);
    return dir;
  }

  /// All generated exports, newest first.
  static Future<List<File>> listExports() async {
    final dir = await exportsDir();
    final files = dir.listSync().whereType<File>().toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
    return files;
  }

  // MARK: Excel

  /// Builds the Excel workbook for [month] (any day inside that month).
  List<int> buildMonthlyWorkbook(DateTime month) {
    final start = startOfMonth(month);
    final end = DateTime(start.year, start.month + 1);
    bool inMonth(DateTime d) => !d.isBefore(start) && d.isBefore(end);

    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    Sheet sheet(String name, List<String> header) {
      final s = excel[name];
      s.isRTL = true;
      s.appendRow(header.map<CellValue?>((h) => TextCellValue(h)).toList());
      for (var i = 0; i < header.length; i++) {
        s.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0)).cellStyle = CellStyle(bold: true);
        s.setColumnWidth(i, 18);
      }
      return s;
    }

    CellValue t(String v) => TextCellValue(v);
    CellValue n(num v) => DoubleCellValue(v.toDouble());
    CellValue d(DateTime? v) =>
        TextCellValue(v == null ? '' : '${Fmt.monthKey(v)}-${v.day.toString().padLeft(2, '0')}');

    final payments = store.allPayments.where((p) => inMonth(p.$1.date)).toList();
    final invoices = store.invoices.all.where((i) => inMonth(i.issueDate)).toList()
      ..sort((a, b) => a.issueDate.compareTo(b.issueDate));
    final expenses = store.expenses.all.where((e) => inMonth(e.date)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final newCustomers = store.customers.all.where((c) => inMonth(c.createdAt)).length;
    final revenue = payments.fold<double>(0, (s, p) => s + p.$1.amount);
    final spent = expenses.fold<double>(0, (s, e) => s + e.amount);
    final sales = invoices.where((i) => i.state == InvoiceState.issued).fold<double>(0, (s, i) => s + i.total);
    final outstanding = store.invoices.all
        .where((i) => i.status.isOutstanding)
        .fold<double>(0, (s, i) => s + i.balance);
    final wonDeals = store.deals.all.where(
      (x) => x.stage == DealStage.won && x.closedAt != null && inMonth(x.closedAt!),
    );

    final summary = sheet('الملخص', ['البند', 'القيمة']);
    for (final row in [
      [t('الشهر'), t(Fmt.monthKey(start))],
      [t('اسم النشاط'), t(store.business.name)],
      [t('العملة'), t(store.business.currency)],
      [t('المحصّل (مدفوعات)'), n(revenue)],
      [t('المبيعات (فواتير صادرة)'), n(sales)],
      [t('عدد الفواتير'), n(invoices.length)],
      [t('المصروفات'), n(spent)],
      [t('صافي الربح'), n(revenue - spent)],
      [t('إجمالي المستحقات الحالية'), n(outstanding)],
      [t('عملاء جدد'), n(newCustomers)],
      [t('صفقات مكسوبة'), n(wonDeals.length)],
      [t('قيمة الصفقات المكسوبة'), n(wonDeals.fold<double>(0, (s, x) => s + x.value))],
    ]) {
      summary.appendRow(row);
    }

    final inv = sheet('الفواتير', [
      'الرقم',
      'العميل',
      'تاريخ الإصدار',
      'الاستحقاق',
      'الحالة',
      'الإجمالي',
      'المدفوع',
      'المتبقي',
    ]);
    for (final i in invoices) {
      inv.appendRow([
        t(i.number),
        t(store.customer(i.customerId)?.name ?? ''),
        d(i.issueDate),
        d(i.dueDate),
        t(i.status.label),
        n(i.total),
        n(i.paidAmount),
        n(i.balance),
      ]);
    }

    final pay = sheet('المدفوعات', ['التاريخ', 'الفاتورة', 'العميل', 'الطريقة', 'المبلغ', 'ملاحظة']);
    for (final p in payments) {
      pay.appendRow([
        d(p.$1.date),
        t(p.$2.number),
        t(store.customer(p.$2.customerId)?.name ?? ''),
        t(p.$1.method.label),
        n(p.$1.amount),
        t(p.$1.note),
      ]);
    }

    final exp = sheet('المصروفات', ['التاريخ', 'البند', 'التصنيف', 'المبلغ', 'ملاحظات']);
    for (final e in expenses) {
      exp.appendRow([d(e.date), t(e.title), t(e.category.label), n(e.amount), t(e.notes)]);
    }

    final cust = sheet('العملاء', [
      'الاسم',
      'الشركة',
      'الهاتف',
      'البريد',
      'المدينة',
      'الحالة',
      'المصدر',
      'الوسوم',
      'إجمالي المشتريات',
      'المدفوع',
      'المستحق',
      'تاريخ الإضافة',
    ]);
    for (final c in store.customers.all..sort((a, b) => a.name.compareTo(b.name))) {
      cust.appendRow([
        t(c.name),
        t(c.company),
        t(c.phone),
        t(c.email),
        t(c.city),
        t(c.status.label),
        t(c.source),
        t(c.tags.join('، ')),
        n(store.totalInvoicedTo(c.id)),
        n(store.totalPaidBy(c.id)),
        n(store.balanceOf(c.id)),
        d(c.createdAt),
      ]);
    }

    final tasks = sheet('المهام', ['المهمة', 'العميل', 'الموعد', 'الأولوية', 'الحالة']);
    for (final task in store.tasks.all.where(
      (x) => x.dueDate != null && inMonth(x.dueDate!) || (x.completedAt != null && inMonth(x.completedAt!)),
    )) {
      tasks.appendRow([
        t(task.title),
        t(store.customer(task.customerId)?.name ?? ''),
        d(task.dueDate),
        t(task.priority.label),
        t(task.isDone ? 'مكتملة' : 'مفتوحة'),
      ]);
    }

    if (defaultSheet != null && defaultSheet != 'الملخص') excel.delete(defaultSheet);
    excel.setDefaultSheet('الملخص');
    return excel.encode() ?? <int>[];
  }

  Future<File> exportMonth(DateTime month) async {
    final bytes = buildMonthlyWorkbook(month);
    final dir = await exportsDir();
    final file = File('${dir.path}/ClientPro-${Fmt.monthKey(month)}.xlsx');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  /// On app start/resume: export last month once, automatically.
  /// Returns the file if a new export was produced.
  Future<File?> autoExportIfDue(DevicePrefs prefs) async {
    if (!prefs.autoMonthlyExport) return null;
    final now = DateTime.now();
    final lastMonth = DateTime(now.year, now.month - 1);
    final key = Fmt.monthKey(lastMonth);
    if (prefs.lastExportedMonth == key) return null;
    try {
      final file = await exportMonth(lastMonth);
      prefs.lastExportedMonth = key;
      return file;
    } catch (e) {
      debugPrint('Auto export failed: $e');
      return null;
    }
  }

  // MARK: Backup

  Future<File> writeBackup() async {
    final dir = await exportsDir();
    final now = DateTime.now();
    final stamp = '${Fmt.monthKey(now)}-${now.day.toString().padLeft(2, '0')}';
    final file = File('${dir.path}/ClientPro-backup-$stamp.json');
    await file.writeAsString(const JsonEncoder.withIndent(' ').convert(store.snapshot()), flush: true);
    return file;
  }

  /// Returns an error message, or null on success.
  String? restoreFromJson(String text, {required bool merge}) {
    final Object? json;
    try {
      json = jsonDecode(text);
    } catch (_) {
      return 'الملف ليس نسخة احتياطية صالحة';
    }
    if (!AppStore.isValidSnapshot(json)) return 'الملف ليس نسخة احتياطية من ClientPro';
    final map = Map<String, dynamic>.from(json as Map);
    if (merge) {
      store.mergeFrom(map);
      store.revision++;
    } else {
      store.replaceWith(map);
    }
    return null;
  }
}
