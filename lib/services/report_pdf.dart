import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import 'format.dart';

enum ReportKind {
  sales('تقرير البيع والشراء والأرباح'),
  daily('تقرير الأرباح اليومية'),
  customers('تقرير العملاء والآجل'),
  inventory('تقرير المخزون وقيمة البضاعة');

  const ReportKind(this.title);
  final String title;

  /// Customers and stock are a snapshot of now; the others cover a period.
  bool get usesPeriod => this == sales || this == daily;
}

/// The PDF engine drops the space after Arabic letters that don't join to
/// the left (ر، د، ا، و، ة...), gluing words together ("تقريرالبيع").
/// Doubling just those spaces brings back a normal-looking gap.
String pdfSpaces(String s) => s.replaceAllMapped(RegExp('([اأإآٱدذرزوؤةء]) '), (m) => '${m[1]}  ');

/// Printable A4 Arabic reports.
class ReportPdf {
  static Future<Uint8List> build(
    AppStore store,
    ReportKind kind, {
    required DateTime from,
    required DateTime to,
    String periodLabel = '',
    int accent = 0xFF2563EB,
  }) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    final color = PdfColor.fromInt(accent);
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );
    final r = _Report(store, color, from, to);

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(28),
        header: (ctx) => r.header(kind.title, kind.usesPeriod ? periodLabel : 'حتى ${Fmt.date(DateTime.now())}'),
        footer: (ctx) => pw.Align(
          alignment: pw.Alignment.center,
          child: pw.Text(
            pdfSpaces('صفحة ${ctx.pageNumber} من ${ctx.pagesCount} • ${Fmt.dateTime(DateTime.now())}'),
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ),
        build: (ctx) => switch (kind) {
          ReportKind.sales => r.sales(),
          ReportKind.daily => r.daily(),
          ReportKind.customers => r.customers(),
          ReportKind.inventory => r.inventory(),
        },
      ),
    );
    return doc.save();
  }
}

class _Report {
  _Report(this.store, this.color, this.from, this.to);
  final AppStore store;
  final PdfColor color;
  final DateTime from;
  final DateTime to;

  String m(double v) => Fmt.money(v);

  pw.Widget header(String title, String subtitle) => pw.Container(
    margin: const pw.EdgeInsets.only(bottom: 12),
    padding: const pw.EdgeInsets.only(bottom: 6),
    decoration: pw.BoxDecoration(
      border: pw.Border(bottom: pw.BorderSide(color: color, width: 2)),
    ),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              pdfSpaces(title),
              style: pw.TextStyle(fontSize: 17, fontWeight: pw.FontWeight.bold, color: color),
            ),
            if (subtitle.isNotEmpty) pw.Text(pdfSpaces(subtitle), style: const pw.TextStyle(fontSize: 10)),
          ],
        ),
        pw.Text(pdfSpaces(store.business.name), style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
      ],
    ),
  );

  /// A grid of label/value boxes.
  pw.Widget summary(List<(String, String)> items) => pw.Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final (label, value) in items)
        pw.Container(
          width: 120,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(color: PdfColors.grey100, borderRadius: pw.BorderRadius.circular(6)),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(pdfSpaces(label), style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700)),
              pw.Text(pdfSpaces(value), style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold)),
            ],
          ),
        ),
    ],
  );

  pw.Widget title(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
    child: pw.Text(
      pdfSpaces(text),
      style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold, color: color),
    ),
  );

  pw.Widget table(List<String> headers, List<List<String>> rows, {List<double>? flex, List<String>? totals}) {
    if (rows.isEmpty) {
      return pw.Text(pdfSpaces('لا يوجد بيانات'), style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600));
    }
    return pw.TableHelper.fromTextArray(
      headers: [for (final h in headers) pdfSpaces(h)],
      data: [
        for (final row in [...rows, ?totals]) [for (final c in row) pdfSpaces(c)],
      ],
      headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold, fontSize: 8.5),
      cellStyle: const pw.TextStyle(fontSize: 8.5),
      headerDecoration: pw.BoxDecoration(color: color),
      cellAlignment: pw.Alignment.centerRight,
      headerAlignment: pw.Alignment.centerRight,
      columnWidths: flex == null ? null : {for (var i = 0; i < flex.length; i++) i: pw.FlexColumnWidth(flex[i])},
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    );
  }

  List<pw.Widget> sales() {
    final sum = store.salesSummary(from: from, to: to);
    final list = store.sales(from: from, to: to).reversed.toList();
    final buys = store.purchasesIn(from: from, to: to).reversed.toList();
    final spent = store.expenses.all.where((e) => !e.date.isBefore(from) && e.date.isBefore(to)).toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    final spentTotal = spent.fold(0.0, (s, e) => s + e.amount);
    final buysTotal = buys.fold(0.0, (s, p) => s + p.total);
    final byCategory = <String, double>{};
    for (final e in spent) {
      byCategory[e.categoryLabel] = (byCategory[e.categoryLabel] ?? 0) + e.amount;
    }

    return [
      summary([
        ('إجمالي المبيعات', m(sum.total)),
        ('بيع نقدي (كاش)', m(sum.cashTotal)),
        ('بيع آجل', m(sum.creditTotal)),
        ('اتحصّل من الآجل', m(sum.creditCollected)),
        ('الخصومات', m(sum.discounts)),
        ('تكلفة البضاعة المباعة', m(sum.cost)),
        ('ربح البيع', m(sum.profit)),
        ('المصروفات', m(spentTotal)),
        ('صافي الربح', m(sum.profit - spentTotal)),
        ('المشتريات (توريد بضاعة)', m(buysTotal)),
        ('عدد عمليات البيع', Fmt.number(sum.count)),
      ]),
      title('الأرباح يوم بيوم'),
      ..._dailyTable(),
      title('المبيعات'),
      table(
        ['التاريخ', 'الرقم', 'النوع', 'العميل', 'الأصناف', 'الخصم', 'الصافي', 'الربح'],
        [
          for (final i in list)
            [
              Fmt.date(i.issueDate),
              i.number,
              i.saleType!.short,
              store.customer(i.customerId)?.name ?? '',
              i.items.map((x) => '${Fmt.number(x.quantity)}× ${x.name}').join('، '),
              i.discount > 0 ? m(i.discount) : '',
              m(i.total),
              m(i.profit),
            ],
        ],
        flex: [1.4, 1.2, 0.8, 1.6, 3.2, 1.1, 1.3, 1.3],
        totals: ['الإجمالي', '', '', '', '', m(sum.discounts), m(sum.total), m(sum.profit)],
      ),
      title('المشتريات (توريد بضاعة)'),
      table(
        ['التاريخ', 'الصنف', 'المورد', 'الكمية', 'سعر الشراء', 'الإجمالي'],
        [
          for (final p in buys)
            [Fmt.date(p.date), p.productName, p.supplier, Fmt.number(p.quantity), m(p.unitCost), m(p.total)],
        ],
        flex: [1.4, 3, 2, 1, 1.4, 1.5],
        totals: ['الإجمالي', '', '', '', '', m(buysTotal)],
      ),
      title('المصروفات حسب النوع'),
      table(
        ['النوع', 'المبلغ'],
        [
          for (final e in byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value))) [e.key, m(e.value)],
        ],
        flex: [3, 1.5],
        totals: ['الإجمالي', m(spentTotal)],
      ),
    ];
  }

  List<pw.Widget> _dailyTable() {
    final days = store.dailyProfit(from, to);
    double sum(double Function(DayProfit) f) => days.fold(0.0, (s, d) => s + f(d));
    return [
      table(
        ['اليوم', 'كاش', 'آجل', 'الخصومات', 'التكلفة', 'ربح البيع', 'المصروفات', 'الصافي'],
        [
          for (final d in days)
            [
              '${Fmt.weekday(d.date).split(' ').first} ${Fmt.date(d.date)}',
              m(d.cash),
              m(d.credit),
              m(d.discounts),
              m(d.cost),
              m(d.profit),
              m(d.expenses),
              m(d.net),
            ],
        ],
        flex: [2.2, 1.2, 1.2, 1.1, 1.2, 1.2, 1.2, 1.3],
        totals: [
          'الإجمالي',
          m(sum((d) => d.cash)),
          m(sum((d) => d.credit)),
          m(sum((d) => d.discounts)),
          m(sum((d) => d.cost)),
          m(sum((d) => d.profit)),
          m(sum((d) => d.expenses)),
          m(sum((d) => d.net)),
        ],
      ),
    ];
  }

  List<pw.Widget> daily() {
    final days = store.dailyProfit(from, to);
    final profit = days.fold(0.0, (s, d) => s + d.profit);
    final spent = days.fold(0.0, (s, d) => s + d.expenses);
    final withSales = days.where((d) => d.count > 0).toList();
    final best = withSales.isEmpty ? null : (withSales.toList()..sort((a, b) => b.profit.compareTo(a.profit))).first;
    return [
      summary([
        ('ربح البيع', m(profit)),
        ('المصروفات', m(spent)),
        ('صافي الربح', m(profit - spent)),
        ('أيام فيها بيع', Fmt.number(withSales.length)),
        ('متوسط ربح اليوم', m(withSales.isEmpty ? 0 : profit / withSales.length)),
        if (best != null) ('أحسن يوم', '${Fmt.date(best.date)} (${m(best.profit)})'),
      ]),
      title('الأرباح يوم بيوم'),
      ..._dailyTable(),
    ];
  }

  List<pw.Widget> customers() {
    final rows = <List<String>>[];
    var owedTotal = 0.0, boughtTotal = 0.0, paidTotal = 0.0;
    final list = store.customers.all.toList()..sort((a, b) => store.balanceOf(b.id).compareTo(store.balanceOf(a.id)));
    for (final c in list) {
      final bought = store.totalInvoicedTo(c.id);
      final paid = store.totalPaidBy(c.id);
      final owed = store.balanceOf(c.id);
      if (bought == 0 && owed == 0) continue;
      final st = store.statementOf(c.id);
      owedTotal += owed;
      boughtTotal += bought;
      paidTotal += paid;
      rows.add([
        c.name,
        c.phone,
        m(bought),
        m(paid),
        owed > 0.009 ? m(owed) : 'مسدد',
        st.isEmpty ? '' : Fmt.date(st.last.date),
      ]);
    }
    final credit = store.creditAccounts();
    return [
      summary([
        ('عدد العملاء', Fmt.number(store.customers.items.length)),
        ('عملاء عليهم آجل', Fmt.number(credit.length)),
        ('إجمالي الآجل عند العملاء', m(owedTotal)),
        ('إجمالي المشتريات', m(boughtTotal)),
        ('إجمالي المدفوع', m(paidTotal)),
      ]),
      title('حسابات العملاء'),
      table(
        ['العميل', 'التليفون', 'إجمالي المشتريات', 'المدفوع', 'الباقي عليه', 'آخر حركة'],
        rows,
        flex: [2.6, 1.8, 1.6, 1.6, 1.5, 1.4],
        totals: ['الإجمالي', '', m(boughtTotal), m(paidTotal), m(owedTotal), ''],
      ),
    ];
  }

  List<pw.Widget> inventory() {
    final items = store.products.all.where((p) => p.trackStock && !p.isService).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final low = items.where((p) => p.isLowStock).toList();
    final atCost = store.inventoryAtCost, atPrice = store.inventoryAtPrice;
    return [
      summary([
        ('قيمة البضاعة بسعر التكلفة', m(atCost)),
        ('قيمة البضاعة بسعر البيع', m(atPrice)),
        ('الربح المتوقع', m(atPrice - atCost)),
        ('عدد الأصناف', Fmt.number(items.length)),
        ('عدد القطع', Fmt.number(store.inventoryUnits)),
        ('أصناف قربت تخلص', Fmt.number(low.length)),
      ]),
      title('المخزون'),
      table(
        ['الصنف', 'الكود', 'الكمية', 'سعر الشراء', 'سعر البيع', 'القيمة بالتكلفة', 'القيمة بالبيع', 'الحالة'],
        [
          for (final p in items)
            [
              p.name,
              p.sku,
              Fmt.number(p.stock),
              m(p.cost),
              m(p.price),
              m(p.stock > 0 ? p.stock * p.cost : 0),
              m(p.stock > 0 ? p.stock * p.price : 0),
              p.stock <= 0 ? 'خلص' : (p.isLowStock ? 'قرب يخلص' : ''),
            ],
        ],
        flex: [2.8, 1.1, 0.9, 1.3, 1.3, 1.5, 1.5, 1.1],
        totals: ['الإجمالي', '', Fmt.number(store.inventoryUnits), '', '', m(atCost), m(atPrice), ''],
      ),
      if (low.isNotEmpty) ...[
        title('محتاج تطلب'),
        table(
          ['الصنف', 'الموجود', 'حد التنبيه'],
          [
            for (final p in low) [p.name, Fmt.number(p.stock), Fmt.number(p.lowStockThreshold)],
          ],
          flex: [3, 1, 1],
        ),
      ],
    ];
  }
}
