import SwiftUI
import SwiftData

struct InvoiceDraftItem: Identifiable {
    let id = UUID()
    var name: String
    var quantity: Double
    var unitPrice: Double
    var product: Product?

    var total: Double { quantity * unitPrice }
}

struct InvoiceFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]

    let invoice: Invoice?

    @State private var customer: Customer?
    @State private var number: String
    @State private var issueDate: Date
    @State private var dueDate: Date
    @State private var items: [InvoiceDraftItem]
    @State private var discount: Double
    @State private var taxRate: Double
    @State private var notes: String
    @State private var showProductPicker = false
    @State private var showNewCustomer = false

    init(invoice: Invoice? = nil, customer: Customer? = nil) {
        self.invoice = invoice
        let defaults = UserDefaults.standard
        let issue = invoice?.issueDate ?? Date()
        let dueDays = defaults.integer(forKey: SettingsKey.defaultDueDays)
        _customer = State(initialValue: invoice?.customer ?? customer)
        _number = State(initialValue: invoice?.number ?? InvoiceNumbering.peekNext())
        _issueDate = State(initialValue: issue)
        _dueDate = State(initialValue: invoice?.dueDate ?? (Calendar.current.date(byAdding: .day, value: dueDays, to: issue) ?? issue))
        _items = State(initialValue: invoice?.sortedItems.map {
            InvoiceDraftItem(name: $0.name, quantity: $0.quantity, unitPrice: $0.unitPrice, product: nil)
        } ?? [])
        _discount = State(initialValue: invoice?.discount ?? 0)
        _taxRate = State(initialValue: invoice?.taxRate ?? defaults.double(forKey: SettingsKey.defaultTaxRate))
        _notes = State(initialValue: invoice?.notes ?? "")
    }

    private var subtotal: Double { items.reduce(0) { $0 + $1.total } }
    private var taxable: Double { max(0, subtotal - discount) }
    private var tax: Double { taxable * taxRate / 100 }
    private var total: Double { taxable + tax }

    private var canSave: Bool {
        !number.trimmingCharacters(in: .whitespaces).isEmpty && items.contains { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("العميل") {
                    Picker("العميل", selection: $customer) {
                        Text("اختر عميلاً").tag(Customer?.none)
                        ForEach(customers) { c in
                            Text(c.name).tag(Customer?.some(c))
                        }
                    }
                    Button {
                        showNewCustomer = true
                    } label: {
                        Label("عميل جديد", systemImage: "person.badge.plus")
                    }
                }

                Section("بيانات الفاتورة") {
                    LabeledContent("رقم الفاتورة") {
                        TextField("رقم الفاتورة", text: $number)
                            .multilineTextAlignment(.trailing)
                    }
                    DatePicker("تاريخ الإصدار", selection: $issueDate, displayedComponents: .date)
                    DatePicker("تاريخ الاستحقاق", selection: $dueDate, in: issueDate..., displayedComponents: .date)
                }

                Section {
                    ForEach($items) { $item in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("اسم المنتج أو الخدمة", text: $item.name)
                                .font(.headline)
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("الكمية").font(.caption2).foregroundStyle(.secondary)
                                    AmountField("1", value: $item.quantity)
                                }
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("السعر").font(.caption2).foregroundStyle(.secondary)
                                    AmountField("0", value: $item.unitPrice)
                                }
                                Spacer()
                                Text(Fmt.money(item.total)).font(.subheadline.bold())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { items.remove(atOffsets: $0) }

                    Button {
                        showProductPicker = true
                    } label: {
                        Label("إضافة من المنتجات والخدمات", systemImage: "shippingbox")
                    }
                    Button {
                        items.append(InvoiceDraftItem(name: "", quantity: 1, unitPrice: 0))
                    } label: {
                        Label("إضافة بند يدوي", systemImage: "plus")
                    }
                } header: {
                    Text("البنود")
                } footer: {
                    if items.isEmpty { Text("أضف بنداً واحداً على الأقل") }
                }

                Section("الإجمالي") {
                    LabeledContent("المجموع الفرعي", value: Fmt.money(subtotal))
                    LabeledContent("الخصم (مبلغ)") {
                        AmountField("0", value: $discount)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    LabeledContent("الضريبة ٪") {
                        AmountField("0", value: $taxRate)
                            .multilineTextAlignment(.trailing)
                            .frame(maxWidth: 120)
                    }
                    if tax > 0 {
                        LabeledContent("قيمة الضريبة", value: Fmt.money(tax))
                    }
                    LabeledContent {
                        Text(Fmt.money(total)).font(.title3.bold())
                    } label: {
                        Text("الإجمالي").font(.headline)
                    }
                }

                Section("ملاحظات تظهر في الفاتورة") {
                    TextField("مثال: بيانات التحويل البنكي أو شروط الدفع", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }

                Section {
                    Button {
                        save(asDraft: false)
                    } label: {
                        Text(invoice == nil || invoice?.state == .draft ? "إصدار الفاتورة" : "حفظ التعديلات")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .disabled(!canSave)
                    if invoice == nil || invoice?.state == .draft {
                        Button {
                            save(asDraft: true)
                        } label: {
                            Text("حفظ كمسودة").frame(maxWidth: .infinity)
                        }
                        .disabled(!canSave)
                    }
                }
            }
            .navigationTitle(invoice == nil ? "فاتورة جديدة" : "تعديل الفاتورة")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save(asDraft: false) }.bold().disabled(!canSave)
                }
            }
            .sheet(isPresented: $showProductPicker) {
                ProductPickerView { product in
                    items.append(InvoiceDraftItem(name: product.name, quantity: 1, unitPrice: product.price, product: product))
                }
                .appEnvironment()
            }
            .sheet(isPresented: $showNewCustomer) {
                CustomerFormView().appEnvironment()
            }
        }
    }

    private func save(asDraft: Bool) {
        let target: Invoice
        let isNew = invoice == nil
        if let invoice {
            target = invoice
            for old in invoice.items ?? [] { context.delete(old) }
        } else {
            target = Invoice(number: number)
            context.insert(target)
            if number == InvoiceNumbering.peekNext() { InvoiceNumbering.advance() }
        }

        target.number = number.trimmingCharacters(in: .whitespaces)
        target.issueDate = issueDate
        target.dueDate = max(dueDate, issueDate)
        target.discount = discount
        target.taxRate = taxRate
        target.notes = notes
        target.customer = customer
        if asDraft {
            target.state = .draft
        } else if target.state == .draft {
            target.state = .issued
        }

        let validItems = items.filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
        for (index, draft) in validItems.enumerated() {
            let item = InvoiceItem(name: draft.name, quantity: draft.quantity, unitPrice: draft.unitPrice, sortIndex: index)
            context.insert(item)
            item.invoice = target
            // Deduct stock only once, when the product is first added to a new invoice.
            if isNew, let product = draft.product, product.trackStock {
                product.stock -= Int(draft.quantity.rounded())
            }
        }

        if let customer, customer.status == .lead || customer.status == .prospect, !asDraft {
            customer.status = .active
        }
        try? context.save()
        dismiss()
    }
}

struct ProductPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Product.name) private var products: [Product]
    @State private var search = ""
    var onPick: (Product) -> Void

    private var filtered: [Product] {
        let active = products.filter { $0.isActive }
        guard !search.isEmpty else { return active }
        return active.filter { $0.name.localizedCaseInsensitiveContains(search) || $0.sku.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { product in
                Button {
                    onPick(product)
                    dismiss()
                } label: {
                    ProductRow(product: product)
                }
                .buttonStyle(.plain)
            }
            .overlay {
                if products.isEmpty {
                    ContentUnavailableView("لا توجد منتجات", systemImage: "shippingbox",
                                           description: Text("أضف منتجاتك وخدماتك من قائمة المزيد ← المنتجات والخدمات"))
                }
            }
            .searchable(text: $search, prompt: "ابحث عن منتج")
            .navigationTitle("اختر منتجاً")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إغلاق") { dismiss() } }
            }
        }
    }
}
