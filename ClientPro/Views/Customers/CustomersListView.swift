import SwiftUI
import SwiftData

struct CustomersListView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Query(sort: \Customer.createdAt, order: .reverse) private var customers: [Customer]

    @State private var search = ""
    @State private var statusFilter: CustomerStatus?
    @State private var tagFilter: String?
    @State private var sort: CustomerSort = .newest
    @State private var favoritesOnly = false
    @State private var showForm = false
    @State private var shareItem: ShareItem?
    @State private var customerToDelete: Customer?

    enum CustomerSort: String, CaseIterable, Identifiable {
        case newest, name, lastContact, revenue, balance
        var id: String { rawValue }
        var title: String {
            switch self {
            case .newest: return "الأحدث"
            case .name: return "الاسم"
            case .lastContact: return "آخر تواصل"
            case .revenue: return "الأكثر شراءً"
            case .balance: return "الأعلى مستحقات"
            }
        }
    }

    private var allTags: [String] {
        Array(Set(customers.flatMap { $0.tags })).sorted()
    }

    private var filtered: [Customer] {
        var list = customers
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            list = list.filter { c in
                c.name.lowercased().contains(query)
                    || c.company.lowercased().contains(query)
                    || c.phone.contains(query)
                    || c.email.lowercased().contains(query)
                    || c.city.lowercased().contains(query)
                    || c.tags.contains { $0.lowercased().contains(query) }
            }
        }
        if let statusFilter { list = list.filter { $0.status == statusFilter } }
        if let tagFilter { list = list.filter { $0.tags.contains(tagFilter) } }
        if favoritesOnly { list = list.filter { $0.isFavorite } }

        switch sort {
        case .newest: break
        case .name: list.sort { $0.name.localizedCompare($1.name) == .orderedAscending }
        case .lastContact: list.sort { ($0.lastContactAt ?? .distantPast) > ($1.lastContactAt ?? .distantPast) }
        case .revenue: list.sort { $0.totalPaid > $1.totalPaid }
        case .balance: list.sort { $0.balance > $1.balance }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                if !customers.isEmpty {
                    filterBar
                        .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
                        .listRowBackground(Color.clear)
                }
                ForEach(filtered) { customer in
                    NavigationLink {
                        CustomerDetailView(customer: customer)
                    } label: {
                        CustomerRow(customer: customer)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            customerToDelete = customer
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                    .swipeActions(edge: .leading) {
                        if let url = ContactActions.callURL(customer.phone) {
                            Button { openURL(url) } label: { Label("اتصال", systemImage: "phone.fill") }
                                .tint(.green)
                        }
                        Button {
                            customer.isFavorite.toggle()
                        } label: {
                            Label("مفضل", systemImage: customer.isFavorite ? "star.slash" : "star.fill")
                        }
                        .tint(.yellow)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if customers.isEmpty {
                    ContentUnavailableView {
                        Label("لا يوجد عملاء بعد", systemImage: "person.2")
                    } description: {
                        Text("أضف أول عميل لتبدأ في متابعة مبيعاتك")
                    } actions: {
                        Button("إضافة عميل") { showForm = true }
                            .buttonStyle(.borderedProminent)
                    }
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: search)
                }
            }
            .navigationTitle("العملاء (\(Fmt.number(customers.count)))")
            .searchable(text: $search, prompt: "ابحث بالاسم أو الهاتف أو الشركة")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Picker("ترتيب حسب", selection: $sort) {
                            ForEach(CustomerSort.allCases) { Text($0.title).tag($0) }
                        }
                        Toggle("المفضلين فقط", systemImage: "star", isOn: $favoritesOnly)
                        if !allTags.isEmpty {
                            Picker("الوسم", selection: $tagFilter) {
                                Text("كل الوسوم").tag(String?.none)
                                ForEach(allTags, id: \.self) { Text($0).tag(String?.some($0)) }
                            }
                        }
                        Divider()
                        Button {
                            if let url = CSVExporter.customers(filtered) { shareItem = ShareItem(url: url) }
                        } label: {
                            Label("تصدير Excel (CSV)", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
            .sheet(isPresented: $showForm) {
                CustomerFormView().appEnvironment()
            }
            .sheet(item: $shareItem) { item in
                ShareSheet(items: [item.url])
            }
            .confirmationDialog("حذف العميل؟", isPresented: Binding(presenting: $customerToDelete),
                                titleVisibility: .visible, presenting: customerToDelete) { customer in
                Button("حذف \(customer.name)", role: .destructive) {
                    context.delete(customer)
                    try? context.save()
                }
            } message: { _ in
                Text("سيتم حذف العميل وكل فواتيره وصفقاته وسجل التواصل معه نهائياً.")
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "الكل", count: customers.count, isSelected: statusFilter == nil) {
                    statusFilter = nil
                }
                ForEach(CustomerStatus.allCases) { status in
                    let count = customers.filter { $0.status == status }.count
                    if count > 0 {
                        FilterChip(title: status.title, count: count, color: status.color, isSelected: statusFilter == status) {
                            statusFilter = statusFilter == status ? nil : status
                        }
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }
}

struct CustomerRow: View {
    let customer: Customer

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(name: customer.name, photoData: customer.photoData, size: 46, color: customer.status.color)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 4) {
                    Text(customer.name).font(.headline).lineLimit(1)
                    if customer.isFavorite {
                        Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                    }
                }
                if !customer.company.isEmpty {
                    Text(customer.company).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                HStack(spacing: 6) {
                    Badge(text: customer.status.title, color: customer.status.color)
                    if let last = customer.lastContactAt {
                        Text(Fmt.relative(last)).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            if customer.balance > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Fmt.compactMoney(customer.balance)).font(.caption.bold()).foregroundStyle(.orange)
                    Text("مستحق").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
