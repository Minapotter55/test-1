import SwiftUI
import SwiftData

struct DealsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Deal.createdAt, order: .reverse) private var deals: [Deal]

    /// nil = all open deals.
    @State private var stage: DealStage?
    @State private var showForm = false
    @State private var editingDeal: Deal?

    private var openDeals: [Deal] { deals.filter { $0.stage.isOpen } }

    private var shown: [Deal] {
        if let stage { return deals.filter { $0.stage == stage } }
        return openDeals
    }

    private var winRate: Double {
        let won = deals.filter { $0.stage == .won }.count
        let lost = deals.filter { $0.stage == .lost }.count
        return won + lost == 0 ? 0 : Double(won) / Double(won + lost) * 100
    }

    private var wonThisMonth: Double {
        let start = Calendar.current.startOfMonth(for: Date())
        return deals.filter { $0.stage == .won && ($0.closedAt ?? .distantPast) >= start }.reduce(0) { $0 + $1.value }
    }

    var body: some View {
        List {
            Section {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    StatCard(title: "قيمة الصفقات المفتوحة", value: Fmt.compactMoney(openDeals.reduce(0) { $0 + $1.value }),
                             icon: "handshake.fill", color: .purple)
                    StatCard(title: "القيمة المتوقعة (مرجّحة)", value: Fmt.compactMoney(openDeals.reduce(0) { $0 + $1.weightedValue }),
                             icon: "scalemass.fill", color: .blue)
                    StatCard(title: "مكسب هذا الشهر", value: Fmt.compactMoney(wonThisMonth),
                             icon: "trophy.fill", color: .green)
                    StatCard(title: "نسبة النجاح", value: Fmt.percent(winRate),
                             icon: "percent", color: .orange)
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        FilterChip(title: "المفتوحة", count: openDeals.count, isSelected: stage == nil) { stage = nil }
                        ForEach(DealStage.allCases) { s in
                            FilterChip(title: s.title, count: deals.filter { $0.stage == s }.count, color: s.color,
                                       isSelected: stage == s) {
                                stage = stage == s ? nil : s
                            }
                        }
                    }
                }
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                ForEach(shown) { deal in
                    Button { editingDeal = deal } label: { DealRow(deal: deal) }
                        .buttonStyle(.plain)
                        .contextMenu { moveMenu(deal) }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { context.delete(deal) } label: { Label("حذف", systemImage: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            if deal.stage.isOpen {
                                Button { deal.stage = .won; deal.probability = 100 } label: { Label("مكسب", systemImage: "trophy.fill") }
                                    .tint(.green)
                                Button { deal.stage = .lost; deal.probability = 0 } label: { Label("خسارة", systemImage: "xmark") }
                                    .tint(.red)
                            }
                        }
                }
            } footer: {
                if !shown.isEmpty {
                    Text("اضغط مطولاً على الصفقة لنقلها لمرحلة أخرى، أو اسحبها لتحديدها كمكسب/خسارة.")
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if deals.isEmpty {
                ContentUnavailableView {
                    Label("لا توجد صفقات", systemImage: "handshake")
                } description: {
                    Text("تابع الفرص البيعية من أول تواصل حتى الإغلاق")
                } actions: {
                    Button("صفقة جديدة") { showForm = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("الصفقات")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(isPresented: $showForm) { DealFormView().appEnvironment() }
        .sheet(item: $editingDeal) { DealFormView(deal: $0).appEnvironment() }
    }

    @ViewBuilder
    private func moveMenu(_ deal: Deal) -> some View {
        ForEach(DealStage.allCases.filter { $0 != deal.stage }) { s in
            Button {
                withAnimation {
                    deal.stage = s
                    deal.probability = s.defaultProbability
                }
            } label: {
                Label("نقل إلى: \(s.title)", systemImage: s.icon)
            }
        }
    }
}

struct DealRow: View {
    let deal: Deal
    var showCustomer = true

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: deal.stage.icon)
                .foregroundStyle(deal.stage.color)
                .frame(width: 36, height: 36)
                .background(deal.stage.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(deal.title).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 4) {
                    if showCustomer, let customer = deal.customer {
                        Text(customer.name)
                        Text("•")
                    }
                    if let close = deal.expectedCloseDate, deal.stage.isOpen {
                        Text("الإغلاق \(Fmt.date(close))")
                    } else {
                        Text(deal.stage.title)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(deal.value)).font(.subheadline.bold())
                if deal.stage.isOpen {
                    Text(Fmt.percent(Double(deal.probability))).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct DealFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]

    let deal: Deal?

    @State private var title: String
    @State private var value: Double
    @State private var stage: DealStage
    @State private var probability: Double
    @State private var customer: Customer?
    @State private var hasCloseDate: Bool
    @State private var closeDate: Date
    @State private var notes: String
    @State private var createInvoice = false

    init(deal: Deal? = nil, customer: Customer? = nil) {
        self.deal = deal
        _title = State(initialValue: deal?.title ?? "")
        _value = State(initialValue: deal?.value ?? 0)
        _stage = State(initialValue: deal?.stage ?? .new)
        _probability = State(initialValue: Double(deal?.probability ?? DealStage.new.defaultProbability))
        _customer = State(initialValue: deal?.customer ?? customer)
        _hasCloseDate = State(initialValue: deal?.expectedCloseDate != nil)
        _closeDate = State(initialValue: deal?.expectedCloseDate ?? (Calendar.current.date(byAdding: .day, value: 30, to: Date()) ?? Date()))
        _notes = State(initialValue: deal?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("عنوان الصفقة *", text: $title)
                    LabeledContent("القيمة") {
                        AmountField("0", value: $value)
                            .multilineTextAlignment(.trailing)
                    }
                    Picker("العميل", selection: $customer) {
                        Text("بدون عميل").tag(Customer?.none)
                        ForEach(customers) { c in Text(c.name).tag(Customer?.some(c)) }
                    }
                }

                Section("المرحلة") {
                    Picker("المرحلة", selection: $stage) {
                        ForEach(DealStage.allCases) { s in
                            Label(s.title, systemImage: s.icon).tag(s)
                        }
                    }
                    .onChange(of: stage) { _, newStage in
                        probability = Double(newStage.defaultProbability)
                    }
                    VStack(alignment: .leading) {
                        Text("احتمال الإغلاق: \(Fmt.percent(probability))")
                        Slider(value: $probability, in: 0...100, step: 5)
                    }
                    Toggle("تاريخ الإغلاق المتوقع", isOn: $hasCloseDate)
                    if hasCloseDate {
                        DatePicker("التاريخ", selection: $closeDate, displayedComponents: .date)
                    }
                    if stage == .won && deal?.stage != .won && customer != nil {
                        Toggle("إنشاء فاتورة بقيمة الصفقة", isOn: $createInvoice)
                    }
                }

                Section("ملاحظات") {
                    TextField("تفاصيل، متطلبات العميل، ...", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(deal == nil ? "صفقة جديدة" : "تعديل الصفقة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target: Deal
        if let deal {
            target = deal
        } else {
            target = Deal(title: title, value: value, stage: stage)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.value = value
        target.stage = stage
        target.probability = Int(probability)
        target.customer = customer
        target.expectedCloseDate = hasCloseDate ? closeDate : nil
        target.notes = notes

        if createInvoice, let customer {
            let invoice = Invoice(number: InvoiceNumbering.peekNext(), issueDate: Date(),
                                  dueDate: Calendar.current.date(byAdding: .day, value: UserDefaults.standard.integer(forKey: SettingsKey.defaultDueDays), to: Date()) ?? Date())
            invoice.taxRate = UserDefaults.standard.double(forKey: SettingsKey.defaultTaxRate)
            context.insert(invoice)
            InvoiceNumbering.advance()
            invoice.customer = customer
            let item = InvoiceItem(name: target.title, quantity: 1, unitPrice: value, sortIndex: 0)
            context.insert(item)
            item.invoice = invoice
            customer.status = customer.status == .vip ? .vip : .active
        }
        try? context.save()
        dismiss()
    }
}
