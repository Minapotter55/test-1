import SwiftUI
import UIKit

/// A file ready to hand to the share sheet.
struct ShareItem: Identifiable {
    let id = UUID()
    let url: URL
}

// MARK: - CSV (opens in Excel / Numbers / Google Sheets)

enum CSVExporter {
    private static func escape(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func write(name: String, header: [String], rows: [[String]]) -> URL? {
        // BOM so Excel shows Arabic correctly.
        var text = "\u{FEFF}" + header.map(escape).joined(separator: ",") + "\n"
        for row in rows {
            text += row.map(escape).joined(separator: ",") + "\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name).csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    private static func plain(_ v: Double) -> String { String(format: "%.2f", v) }

    private static func isoDate(_ d: Date?) -> String {
        guard let d else { return "" }
        return d.formatted(.iso8601.year().month().day())
    }

    static func customers(_ customers: [Customer]) -> URL? {
        let header = ["الاسم", "الشركة", "الهاتف", "واتساب", "البريد", "المدينة", "العنوان", "الحالة", "المصدر", "الوسوم", "التقييم", "إجمالي الفواتير", "المدفوع", "المستحق", "تاريخ الإضافة", "ملاحظات"]
        let rows = customers.map { c in
            [c.name, c.company, c.phone, c.whatsapp, c.email, c.city, c.address, c.status.title, c.source,
             c.tags.joined(separator: " | "), String(c.rating), plain(c.totalInvoiced), plain(c.totalPaid),
             plain(c.balance), isoDate(c.createdAt), c.notes]
        }
        return write(name: "العملاء", header: header, rows: rows)
    }

    static func invoices(_ invoices: [Invoice]) -> URL? {
        let header = ["رقم الفاتورة", "العميل", "تاريخ الإصدار", "تاريخ الاستحقاق", "الحالة", "المجموع الفرعي", "الخصم", "الضريبة", "الإجمالي", "المدفوع", "المتبقي"]
        let rows = invoices.map { i in
            [i.number, i.customer?.name ?? "", isoDate(i.issueDate), isoDate(i.dueDate), i.status.title,
             plain(i.subtotal), plain(i.discount), plain(i.taxAmount), plain(i.total), plain(i.paidAmount), plain(i.balance)]
        }
        return write(name: "الفواتير", header: header, rows: rows)
    }

    static func expenses(_ expenses: [Expense]) -> URL? {
        let header = ["البند", "التصنيف", "المبلغ", "التاريخ", "ملاحظات"]
        let rows = expenses.map { e in
            [e.title, e.category.title, plain(e.amount), isoDate(e.date), e.notes]
        }
        return write(name: "المصروفات", header: header, rows: rows)
    }
}

// MARK: - Share sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Invoice PDF

enum InvoicePDF {
    @MainActor
    static func render(_ invoice: Invoice) -> URL? {
        let page = InvoicePDFView(invoice: invoice)
            .frame(width: 595)
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Fmt.locale)
            .environment(\.colorScheme, .light)

        let renderer = ImageRenderer(content: page)
        renderer.proposedSize = ProposedViewSize(width: 595, height: nil)

        let safeName = invoice.number.replacingOccurrences(of: "/", with: "-")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("فاتورة-\(safeName).pdf")

        var ok = false
        renderer.render { size, draw in
            var box = CGRect(x: 0, y: 0, width: size.width, height: max(size.height, 842))
            guard let pdf = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
            pdf.beginPDFPage(nil)
            // Draw at the top of an A4-or-taller page.
            pdf.translateBy(x: 0, y: box.height - size.height)
            draw(pdf)
            pdf.endPDFPage()
            pdf.closePDF()
            ok = true
        }
        return ok ? url : nil
    }
}

/// The printable invoice layout (A4 width).
struct InvoicePDFView: View {
    let invoice: Invoice

    private var defaults: UserDefaults { .standard }
    private var businessName: String { defaults.string(forKey: SettingsKey.businessName) ?? "" }
    private var businessPhone: String { defaults.string(forKey: SettingsKey.businessPhone) ?? "" }
    private var businessEmail: String { defaults.string(forKey: SettingsKey.businessEmail) ?? "" }
    private var businessAddress: String { defaults.string(forKey: SettingsKey.businessAddress) ?? "" }
    private var businessTaxID: String { defaults.string(forKey: SettingsKey.businessTaxID) ?? "" }
    private var footer: String { defaults.string(forKey: SettingsKey.invoiceFooter) ?? "" }
    private var logo: UIImage? {
        guard let data = defaults.data(forKey: SettingsKey.businessLogo) else { return nil }
        return UIImage(data: data)
    }
    private var accent: Color { AppTheme.accent(defaults.integer(forKey: SettingsKey.accent)) }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            Divider()
            billTo
            itemsTable
            totals
            if !invoice.notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("ملاحظات").font(.caption.bold()).foregroundStyle(.secondary)
                    Text(invoice.notes).font(.callout)
                }
            }
            Spacer(minLength: 10)
            if !footer.isEmpty {
                Text(footer)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(40)
        .background(Color.white)
        .foregroundStyle(Color.black)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let logo {
                    Image(uiImage: logo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 90, maxHeight: 70)
                }
                Text(businessName.isEmpty ? "اسم النشاط" : businessName)
                    .font(.title2.bold())
                ForEach([businessAddress, businessPhone, businessEmail].filter { !$0.isEmpty }, id: \.self) { line in
                    Text(line).font(.caption).foregroundStyle(.secondary)
                }
                if !businessTaxID.isEmpty {
                    Text("الرقم الضريبي: \(businessTaxID)").font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 6) {
                Text(invoice.state == .draft ? "مسودة فاتورة" : "فاتورة")
                    .font(.largeTitle.bold())
                    .foregroundStyle(accent)
                Text("رقم: \(invoice.number)").font(.callout.bold())
                Text("تاريخ الإصدار: \(Fmt.date(invoice.issueDate))").font(.caption)
                Text("تاريخ الاستحقاق: \(Fmt.date(invoice.dueDate))").font(.caption)
                Text(invoice.status.title)
                    .font(.caption.bold())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(invoice.status.color.opacity(0.15), in: Capsule())
                    .foregroundStyle(invoice.status.color)
            }
        }
    }

    private var billTo: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("فاتورة إلى").font(.caption.bold()).foregroundStyle(.secondary)
            if let c = invoice.customer {
                Text(c.name).font(.headline)
                if !c.company.isEmpty { Text(c.company).font(.callout) }
                if !c.phone.isEmpty { Text(c.phone).font(.caption) }
                if !c.address.isEmpty || !c.city.isEmpty {
                    Text([c.address, c.city].filter { !$0.isEmpty }.joined(separator: "، ")).font(.caption)
                }
            } else {
                Text("—")
            }
        }
    }

    private var itemsTable: some View {
        VStack(spacing: 0) {
            HStack {
                Text("البند").frame(maxWidth: .infinity, alignment: .leading)
                Text("الكمية").frame(width: 60)
                Text("السعر").frame(width: 90)
                Text("الإجمالي").frame(width: 100, alignment: .trailing)
            }
            .font(.caption.bold())
            .foregroundStyle(.white)
            .padding(10)
            .background(accent)

            ForEach(Array(invoice.sortedItems.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.name).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Fmt.number(item.quantity)).frame(width: 60)
                    Text(Fmt.money(item.unitPrice)).frame(width: 90)
                    Text(Fmt.money(item.total)).frame(width: 100, alignment: .trailing)
                }
                .font(.callout)
                .padding(10)
                .background(index % 2 == 0 ? Color.gray.opacity(0.06) : Color.clear)
            }
        }
        .overlay(Rectangle().stroke(Color.gray.opacity(0.25)))
    }

    private var totals: some View {
        HStack {
            Spacer()
            VStack(spacing: 6) {
                totalRow("المجموع الفرعي", invoice.subtotal)
                if invoice.discount > 0 { totalRow("الخصم", -invoice.discount) }
                if invoice.taxRate > 0 { totalRow("الضريبة (\(Fmt.number(invoice.taxRate))٪)", invoice.taxAmount) }
                Divider()
                totalRow("الإجمالي", invoice.total, bold: true)
                if invoice.paidAmount > 0 {
                    totalRow("المدفوع", invoice.paidAmount)
                    totalRow("المتبقي", invoice.balance, bold: true)
                }
            }
            .frame(width: 260)
        }
    }

    private func totalRow(_ title: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(Fmt.money(value))
        }
        .font(bold ? .headline : .callout)
    }
}
