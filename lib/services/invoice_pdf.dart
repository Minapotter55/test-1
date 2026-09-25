import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../data/store.dart';
import '../models/models.dart';
import 'format.dart';

/// Builds an A4 Arabic (RTL) invoice PDF with the business logo.
class InvoicePdf {
  static Future<Uint8List> build(AppStore store, Invoice invoice, {int accent = 0xFF2563EB}) async {
    final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Regular.ttf'));
    final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/Tajawal-Bold.ttf'));
    final b = store.business;
    final customer = store.customer(invoice.customerId);
    final color = PdfColor.fromInt(accent);
    final status = invoice.status;

    pw.MemoryImage? logo;
    if (b.logoBase64.isNotEmpty) {
      try {
        logo = pw.MemoryImage(base64Decode(b.logoBase64));
      } catch (_) {}
    }

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold),
    );

    pw.Widget totalRow(String label, double value, {bool strong = false}) => pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label, style: pw.TextStyle(fontWeight: strong ? pw.FontWeight.bold : null)),
          pw.Text(Fmt.money(value), style: pw.TextStyle(fontWeight: strong ? pw.FontWeight.bold : null)),
        ],
      ),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        textDirection: pw.TextDirection.rtl,
        margin: const pw.EdgeInsets.all(36),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  if (logo != null) pw.Image(logo, width: 80, height: 60, fit: pw.BoxFit.contain),
                  pw.Text(
                    b.name.isEmpty ? 'اسم النشاط' : b.name,
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  for (final line in [b.address, b.phone, b.email].where((s) => s.isNotEmpty))
                    pw.Text(line, style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
                  if (b.taxId.isNotEmpty)
                    pw.Text(
                      'الرقم الضريبي: ${b.taxId}',
                      style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
                    ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    invoice.state == InvoiceState.draft ? 'مسودة فاتورة' : 'فاتورة',
                    style: pw.TextStyle(fontSize: 26, fontWeight: pw.FontWeight.bold, color: color),
                  ),
                  pw.Text('رقم: ${invoice.number}', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  pw.Text('تاريخ الإصدار: ${Fmt.date(invoice.issueDate)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.Text('تاريخ الاستحقاق: ${Fmt.date(invoice.dueDate)}', style: const pw.TextStyle(fontSize: 10)),
                  pw.SizedBox(height: 4),
                  pw.Container(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: pw.BoxDecoration(
                      color: PdfColor.fromInt(status.color.toARGB32()).shade(0.1),
                      borderRadius: pw.BorderRadius.circular(8),
                    ),
                    child: pw.Text(status.label, style: const pw.TextStyle(fontSize: 9)),
                  ),
                ],
              ),
            ],
          ),
          pw.Divider(color: PdfColors.grey300),
          pw.Text('فاتورة إلى', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
          pw.Text(customer?.name ?? '—', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          if (customer != null && customer.company.isNotEmpty) pw.Text(customer.company),
          if (customer != null && customer.phone.isNotEmpty)
            pw.Text(customer.phone, style: const pw.TextStyle(fontSize: 10)),
          if (customer != null && (customer.address.isNotEmpty || customer.city.isNotEmpty))
            pw.Text(
              [customer.address, customer.city].where((s) => s.isNotEmpty).join('، '),
              style: const pw.TextStyle(fontSize: 10),
            ),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: ['البند', 'الكمية', 'السعر', 'الإجمالي'],
            data: [
              for (final item in invoice.items)
                [item.name, Fmt.number(item.quantity), Fmt.money(item.unitPrice), Fmt.money(item.total)],
            ],
            headerStyle: pw.TextStyle(color: PdfColors.white, fontWeight: pw.FontWeight.bold),
            headerDecoration: pw.BoxDecoration(color: color),
            cellAlignment: pw.Alignment.centerRight,
            headerAlignment: pw.Alignment.centerRight,
            columnWidths: {
              0: const pw.FlexColumnWidth(4),
              1: const pw.FlexColumnWidth(1.2),
              2: const pw.FlexColumnWidth(2),
              3: const pw.FlexColumnWidth(2),
            },
            oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          ),
          pw.SizedBox(height: 12),
          pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.SizedBox(
              width: 230,
              child: pw.Column(
                children: [
                  totalRow('المجموع الفرعي', invoice.subtotal),
                  if (invoice.discount > 0) totalRow('الخصم', -invoice.discount),
                  if (invoice.taxRate > 0) totalRow('الضريبة (${Fmt.number(invoice.taxRate)}٪)', invoice.taxAmount),
                  pw.Divider(color: PdfColors.grey400),
                  totalRow('الإجمالي', invoice.total, strong: true),
                  if (invoice.paidAmount > 0) ...[
                    totalRow('المدفوع', invoice.paidAmount),
                    totalRow('المتبقي', invoice.balance, strong: true),
                  ],
                ],
              ),
            ),
          ),
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 16),
            pw.Text('ملاحظات', style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700)),
            pw.Text(invoice.notes),
          ],
          if (b.invoiceFooter.isNotEmpty) ...[
            pw.SizedBox(height: 30),
            pw.Center(
              child: pw.Text(b.invoiceFooter, style: const pw.TextStyle(color: PdfColors.grey700)),
            ),
          ],
        ],
      ),
    );
    return doc.save();
  }
}
