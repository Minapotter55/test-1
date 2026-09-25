import SwiftUI
import SwiftData

struct ProductsView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Product.name) private var products: [Product]

    @State private var search = ""
    @State private var showForm = false
    @State private var editing: Product?

    private var filtered: [Product] {
        guard !search.isEmpty else { return products }
        return products.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || $0.sku.localizedCaseInsensitiveContains(search)
                || $0.category.localizedCaseInsensitiveContains(search)
        }
    }

    private var grouped: [(String, [Product])] {
        let dict = Dictionary(grouping: filtered) { $0.category.isEmpty ? "بدون تصنيف" : $0.category }
        return dict.keys.sorted().map { ($0, dict[$0] ?? []) }
    }

    private var stockValue: Double {
        products.filter { $0.trackStock }.reduce(0) { $0 + Double(max(0, $1.stock)) * $1.cost }
    }

    var body: some View {
        List {
            if !products.isEmpty {
                Section {
                    HStack(spacing: 10) {
                        StatCard(title: "منتجات وخدمات", value: Fmt.number(products.count), icon: "shippingbox.fill", color: .blue)
                        StatCard(title: "قيمة المخزون", value: Fmt.compactMoney(stockValue), icon: "archivebox.fill", color: .teal,
                                 subtitle: products.filter(\.isLowStock).isEmpty ? nil : "\(Fmt.number(products.filter(\.isLowStock).count)) منخفض")
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            ForEach(grouped, id: \.0) { group in
                Section(group.0) {
                    ForEach(group.1) { product in
                        Button { editing = product } label: { ProductRow(product: product) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { context.delete(product) } label: { Label("حذف", systemImage: "trash") }
                            }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if products.isEmpty {
                ContentUnavailableView {
                    Label("لا توجد منتجات أو خدمات", systemImage: "shippingbox")
                } description: {
                    Text("أضف ما تبيعه لتستخدمه بسرعة في الفواتير وتتابع المخزون")
                } actions: {
                    Button("إضافة") { showForm = true }.buttonStyle(.borderedProminent)
                }
            } else if filtered.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
        .searchable(text: $search, prompt: "ابحث بالاسم أو الكود")
        .navigationTitle("المنتجات والخدمات")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
        }
        .sheet(isPresented: $showForm) { ProductFormView().appEnvironment() }
        .sheet(item: $editing) { ProductFormView(product: $0).appEnvironment() }
    }
}

struct ProductRow: View {
    let product: Product

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: product.isService ? "wrench.and.screwdriver.fill" : "shippingbox.fill")
                .foregroundStyle(product.isService ? Color.purple : Color.blue)
                .frame(width: 36, height: 36)
                .background((product.isService ? Color.purple : Color.blue).opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(product.name).font(.subheadline.bold()).lineLimit(1)
                HStack(spacing: 6) {
                    if !product.sku.isEmpty { Text(product.sku) }
                    if product.cost > 0 { Text("ربح \(Fmt.percent(product.marginPercent))") }
                    if !product.isActive { Text("موقوف") }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(Fmt.money(product.price)).font(.subheadline.bold())
                if product.trackStock {
                    Badge(text: "مخزون \(Fmt.number(product.stock))",
                          color: product.stock <= 0 ? .red : (product.isLowStock ? .orange : .green))
                }
            }
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
    }
}

struct ProductFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var products: [Product]

    let product: Product?

    @State private var name: String
    @State private var sku: String
    @State private var category: String
    @State private var price: Double
    @State private var cost: Double
    @State private var isService: Bool
    @State private var trackStock: Bool
    @State private var stock: Int
    @State private var lowStock: Int
    @State private var isActive: Bool
    @State private var notes: String

    init(product: Product? = nil) {
        self.product = product
        _name = State(initialValue: product?.name ?? "")
        _sku = State(initialValue: product?.sku ?? "")
        _category = State(initialValue: product?.category ?? "")
        _price = State(initialValue: product?.price ?? 0)
        _cost = State(initialValue: product?.cost ?? 0)
        _isService = State(initialValue: product?.isService ?? false)
        _trackStock = State(initialValue: product?.trackStock ?? false)
        _stock = State(initialValue: product?.stock ?? 0)
        _lowStock = State(initialValue: product?.lowStockThreshold ?? 5)
        _isActive = State(initialValue: product?.isActive ?? true)
        _notes = State(initialValue: product?.notes ?? "")
    }

    private var categories: [String] {
        Array(Set(products.map(\.category).filter { !$0.isEmpty })).sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("النوع", selection: $isService) {
                        Text("منتج").tag(false)
                        Text("خدمة").tag(true)
                    }
                    .pickerStyle(.segmented)
                    TextField("الاسم *", text: $name)
                    TextField("الكود / SKU", text: $sku)
                    HStack {
                        TextField("التصنيف", text: $category)
                        if !categories.isEmpty {
                            Menu {
                                ForEach(categories, id: \.self) { c in Button(c) { category = c } }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                            }
                        }
                    }
                }
                Section("التسعير") {
                    LabeledContent("سعر البيع") {
                        AmountField("0", value: $price).multilineTextAlignment(.trailing)
                    }
                    LabeledContent("التكلفة") {
                        AmountField("0", value: $cost).multilineTextAlignment(.trailing)
                    }
                    if price > 0 && cost > 0 {
                        LabeledContent("هامش الربح", value: "\(Fmt.money(price - cost)) (\(Fmt.percent((price - cost) / price * 100)))")
                    }
                }
                if !isService {
                    Section("المخزون") {
                        Toggle("متابعة المخزون", isOn: $trackStock)
                        if trackStock {
                            Stepper("الكمية الحالية: \(Fmt.number(stock))", value: $stock, in: -1000...100000)
                            Stepper("تنبيه عند: \(Fmt.number(lowStock))", value: $lowStock, in: 0...1000)
                        }
                    }
                }
                Section {
                    Toggle("متاح للبيع", isOn: $isActive)
                    TextField("ملاحظات", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(product == nil ? "إضافة منتج/خدمة" : "تعديل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }.bold().disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        let target: Product
        if let product {
            target = product
        } else {
            target = Product(name: name, price: price)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.sku = sku
        target.category = category.trimmingCharacters(in: .whitespaces)
        target.price = price
        target.cost = cost
        target.isService = isService
        target.trackStock = !isService && trackStock
        target.stock = stock
        target.lowStockThreshold = lowStock
        target.isActive = isActive
        target.notes = notes
        try? context.save()
        dismiss()
    }
}
