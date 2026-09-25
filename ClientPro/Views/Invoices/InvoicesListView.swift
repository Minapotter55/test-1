import SwiftUI
import SwiftData

struct InvoicesListView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Invoice.issueDate, order: .reverse) private var invoices: [Invoice]

    @State private var search = ""
    @State private var filter: InvoiceStatus?
    @State private var showForm = false
    @State private var shareItem: ShareItem?
    @State private var invoiceToDelete: Invoice?

    private var filtered: [Invoice] {
        var list = invoices
        if let filter { list = list.filter { $0.status == filter } }
        let q = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !q.isEmpty {
            list = list.filter {
                $0.number.lowercased().contains(q) || ($0.customer?.name.lowercased().contains(q) ?? false)
            }
        }
        return list
    }

    private var outstanding: Double {
        invoices.filter { $0.status.isOutstanding }.reduce(0) { $0 + $1.balance }
    }

    private var overdueTotal: Double {
        invoices.filter { $0.status == .overdue }.reduce(0) { $0 + $1.balance }
    }

    private var collectedThisMonth: Double {
        let start = Calendar.current.startOfMonth(for: Date())
        return invoices.flatMap { $0.payments ?? [] }.filter { $0.date >= start }.reduce(0) { $0 + $1.amount }
    }

    var body: some View {
        NavigationStack {
            List {
                if !invoices.isEmpty {
                    Section {
                        HStack(spacing: 10) {
                            summaryTile("مستحقات", outstanding, .orange)
                            summaryTile("متأخرات", overdueTotal, .red)
                            summaryTile("تحصيل الشهر", collectedThisMonth, .green)
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                FilterChip(title: "الكل", count: invoices.count, isSelected: filter == nil) { filter = nil }
                                ForEach(InvoiceStatus.allCases) { status in
                                    let count = invoices.filter { $0.status == status }.count
                                    if count > 0 {
                                        FilterChip(title: status.title, count: count, color: status.color, isSelected: filter == status) {
                                            filter = filter == status ? nil : status
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }

                Section {
                    ForEach(filtered) { invoice in
                        NavigationLink {
                            InvoiceDetailView(invoice: invoice)
                        } label: {
                            InvoiceRow(invoice: invoice)
                        }
                        .swipeActions {
                            Button(role: .destructive) { invoiceToDelete = invoice } label: {
                                Label("حذف", systemImage: "trash")
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if invoices.isEmpty {
                    ContentUnavailableView {
                        Label("لا توجد فواتير", systemImage: "doc.text")
                    } description: {
                        Text("أنشئ فاتورة واطبعها أو أرسلها للعميل PDF على واتساب")
                    } actions: {
                        Button("فاتورة جديدة") { showForm = true }.buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("الفواتير")
            .searchable(text: $search, prompt: "رقم الفاتورة أو اسم العميل")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        if let url = CSVExporter.invoices(filtered) { shareItem = ShareItem(url: url) }
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(invoices.isEmpty)
                }
            }
            .sheet(isPresented: $showForm) { InvoiceFormView().appEnvironment() }
            .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
            .confirmationDialog("حذف الفاتورة؟", isPresented: Binding(presenting: $invoiceToDelete),
                                titleVisibility: .visible, presenting: invoiceToDelete) { invoice in
                Button("حذف \(invoice.number)", role: .destructive) {
                    context.delete(invoice)
                    try? context.save()
                }
            } message: { _ in
                Text("سيتم حذف الفاتورة وكل المدفوعات المسجلة عليها.")
            }
        }
    }

    private func summaryTile(_ title: String, _ value: Double, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(Fmt.compactMoney(value)).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct InvoiceRow: View {
    let invoice: Invoice
    var showCustomer = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: invoice.status.icon)
                .foregroundStyle(invoice.status.color)
                .frame(width: 36, height: 36)
                .background(invoice.status.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(showCustomer ? (invoice.customer?.name ?? "بدون عميل") : invoice.number)
                    .font(.subheadline.bold())
                    .lineLimit(1)
                Text(showCustomer ? "\(invoice.number) • \(Fmt.date(invoice.issueDate))" : Fmt.date(invoice.issueDate))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(invoice.total)).font(.subheadline.bold())
                Badge(text: invoice.status.title, color: invoice.status.color)
            }
        }
        .padding(.vertical, 2)
    }
}
