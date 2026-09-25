import SwiftUI
import SwiftData

struct InvoiceDetailView: View {
    @Bindable var invoice: Invoice
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.businessName) private var businessName = ""

    @State private var showEdit = false
    @State private var showPayment = false
    @State private var shareItem: ShareItem?
    @State private var confirmDelete = false
    @State private var duplicated: Invoice?

    var body: some View {
        List {
            Section {
                VStack(spacing: 8) {
                    Badge(text: invoice.status.title, color: invoice.status.color, icon: invoice.status.icon)
                    Text(Fmt.money(invoice.total)).font(.largeTitle.bold())
                    if invoice.status.isOutstanding && invoice.paidAmount > 0 {
                        Text("المتبقي \(Fmt.money(invoice.balance))").foregroundStyle(.orange)
                    }
                    if invoice.state == .issued && invoice.total > 0 {
                        ProgressView(value: min(1, invoice.paidAmount / invoice.total))
                            .tint(.green)
                            .padding(.horizontal, 40)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .listRowBackground(Color.clear)

            Section {
                actionsRow
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section("التفاصيل") {
                LabeledContent("رقم الفاتورة", value: invoice.number)
                if let customer = invoice.customer {
                    NavigationLink {
                        CustomerDetailView(customer: customer)
                    } label: {
                        LabeledContent("العميل", value: customer.name)
                    }
                }
                LabeledContent("تاريخ الإصدار", value: Fmt.date(invoice.issueDate))
                LabeledContent("تاريخ الاستحقاق") {
                    Text(Fmt.date(invoice.dueDate))
                        .foregroundStyle(invoice.status == .overdue ? Color.red : Color.secondary)
                }
            }

            Section("البنود") {
                ForEach(invoice.sortedItems) { item in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name)
                            Text("\(Fmt.number(item.quantity)) × \(Fmt.money(item.unitPrice))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.money(item.total))
                    }
                }
                LabeledContent("المجموع الفرعي", value: Fmt.money(invoice.subtotal))
                if invoice.discount > 0 {
                    LabeledContent("الخصم", value: "- " + Fmt.money(invoice.discount))
                }
                if invoice.taxRate > 0 {
                    LabeledContent("الضريبة \(Fmt.number(invoice.taxRate))٪", value: Fmt.money(invoice.taxAmount))
                }
                LabeledContent {
                    Text(Fmt.money(invoice.total)).bold()
                } label: {
                    Text("الإجمالي").bold()
                }
            }

            Section {
                ForEach(invoice.sortedPayments) { payment in
                    HStack {
                        Image(systemName: payment.method.icon).foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(payment.method.title)
                            Text(Fmt.date(payment.date) + (payment.note.isEmpty ? "" : " • \(payment.note)"))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(Fmt.money(payment.amount)).foregroundStyle(.green)
                    }
                    .swipeActions {
                        Button(role: .destructive) { context.delete(payment) } label: { Label("حذف", systemImage: "trash") }
                    }
                }
                if invoice.state == .issued && invoice.balance > 0 {
                    Button { showPayment = true } label: {
                        Label("تسجيل دفعة", systemImage: "plus.circle.fill")
                    }
                }
            } header: {
                Text("المدفوعات (\(Fmt.money(invoice.paidAmount)))")
            }

            if !invoice.notes.isEmpty {
                Section("ملاحظات") { Text(invoice.notes) }
            }

            Section {
                if invoice.state == .draft {
                    Button { invoice.state = .issued } label: { Label("إصدار الفاتورة", systemImage: "checkmark.seal") }
                }
                if invoice.state == .issued && invoice.balance > 0 {
                    Button { markPaid() } label: { Label("تحديد كمدفوعة بالكامل", systemImage: "checkmark.circle") }
                }
                Button { duplicate() } label: { Label("نسخ الفاتورة", systemImage: "plus.square.on.square") }
                if invoice.state == .cancelled {
                    Button { invoice.state = .issued } label: { Label("إعادة تفعيل", systemImage: "arrow.uturn.backward") }
                } else {
                    Button(role: .destructive) { invoice.state = .cancelled } label: { Label("إلغاء الفاتورة", systemImage: "xmark.circle") }
                }
                Button(role: .destructive) { confirmDelete = true } label: { Label("حذف", systemImage: "trash") }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(invoice.number)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("تعديل") { showEdit = true }
            }
        }
        .sheet(isPresented: $showEdit) { InvoiceFormView(invoice: invoice).appEnvironment() }
        .sheet(isPresented: $showPayment) { PaymentFormView(invoice: invoice).appEnvironment() }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .sheet(item: $duplicated) { copy in
            InvoiceFormView(invoice: copy).appEnvironment()
        }
        .confirmationDialog("حذف الفاتورة؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف نهائياً", role: .destructive) { deleteInvoice() }
        }
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            action("PDF", "doc.richtext.fill", .blue) { sharePDF() }
            action("تذكير", "message.fill", .green, enabled: invoice.customer.map { !$0.whatsappNumber.isEmpty } ?? false) {
                sendReminder()
            }
            action("دفعة", "banknote.fill", .orange, enabled: invoice.state == .issued && invoice.balance > 0) {
                showPayment = true
            }
            action("تعديل", "pencil", .purple) { showEdit = true }
        }
    }

    private func action(_ title: String, _ icon: String, _ color: Color, enabled: Bool = true, perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background((enabled ? color : .gray).opacity(0.15), in: Circle())
                    .foregroundStyle(enabled ? color : .gray)
                Text(title).font(.caption2).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
    }

    private func sharePDF() {
        if let url = InvoicePDF.render(invoice) { shareItem = ShareItem(url: url) }
    }

    private func sendReminder() {
        guard let customer = invoice.customer else { return }
        var message = "مرحباً \(customer.name)،\n"
        if invoice.status == .paid {
            message += "نشكركم على سداد الفاتورة رقم \(invoice.number) بمبلغ \(Fmt.money(invoice.total))."
        } else {
            message += "نود تذكيركم بالفاتورة رقم \(invoice.number) بتاريخ \(Fmt.date(invoice.issueDate))"
            message += "\nالمبلغ المتبقي: \(Fmt.money(invoice.balance))"
            message += "\nتاريخ الاستحقاق: \(Fmt.date(invoice.dueDate))"
        }
        if !businessName.isEmpty { message += "\n\n\(businessName)" }
        if let url = ContactActions.whatsappURL(customer.whatsappNumber, text: message) {
            openURL(url)
            let log = Interaction(type: .whatsapp, summary: "تذكير بالفاتورة \(invoice.number)")
            context.insert(log)
            log.customer = customer
            customer.lastContactAt = Date()
        }
    }

    private func markPaid() {
        let payment = Payment(amount: invoice.balance, method: .cash)
        context.insert(payment)
        payment.invoice = invoice
        try? context.save()
    }

    private func duplicate() {
        let copy = Invoice(number: InvoiceNumbering.peekNext(), issueDate: Date(),
                           dueDate: Calendar.current.date(byAdding: .day, value: UserDefaults.standard.integer(forKey: SettingsKey.defaultDueDays), to: Date()) ?? Date())
        copy.state = .draft
        copy.discount = invoice.discount
        copy.taxRate = invoice.taxRate
        copy.notes = invoice.notes
        context.insert(copy)
        InvoiceNumbering.advance()
        copy.customer = invoice.customer
        for item in invoice.sortedItems {
            let newItem = InvoiceItem(name: item.name, quantity: item.quantity, unitPrice: item.unitPrice, sortIndex: item.sortIndex)
            context.insert(newItem)
            newItem.invoice = copy
        }
        try? context.save()
        duplicated = copy
    }

    private func deleteInvoice() {
        let target = invoice
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(target)
            try? context.save()
        }
    }
}

struct PaymentFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    let invoice: Invoice

    @State private var amount: Double
    @State private var date = Date()
    @State private var method: PaymentMethod = .cash
    @State private var note = ""

    init(invoice: Invoice) {
        self.invoice = invoice
        _amount = State(initialValue: invoice.balance)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    AmountField("المبلغ", value: $amount)
                        .font(.title2.bold())
                    HStack {
                        Button("كامل المتبقي") { amount = invoice.balance }
                        Spacer()
                        Button("النصف") { amount = (invoice.balance / 2).rounded() }
                    }
                    .buttonStyle(.bordered)
                } header: {
                    Text("المتبقي \(Fmt.money(invoice.balance))")
                }
                Section {
                    Picker("طريقة الدفع", selection: $method) {
                        ForEach(PaymentMethod.allCases) { m in
                            Label(m.title, systemImage: m.icon).tag(m)
                        }
                    }
                    DatePicker("التاريخ", selection: $date, displayedComponents: .date)
                    TextField("ملاحظة (اختياري)", text: $note)
                }
            }
            .navigationTitle("تسجيل دفعة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.bold().disabled(amount <= 0)
                }
            }
        }
    }

    private func save() {
        let payment = Payment(amount: amount, date: date, method: method, note: note)
        context.insert(payment)
        payment.invoice = invoice
        try? context.save()
        dismiss()
    }
}
