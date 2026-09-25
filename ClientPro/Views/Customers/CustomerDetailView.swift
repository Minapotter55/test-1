import SwiftUI
import SwiftData

struct CustomerDetailView: View {
    @Bindable var customer: Customer
    @Environment(\.modelContext) private var context
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    @State private var tab: DetailTab = .activity
    @State private var sheet: DetailSheet?
    @State private var editingDeal: Deal?
    @State private var editingTask: TaskItem?
    @State private var confirmDelete = false

    enum DetailTab: String, CaseIterable, Identifiable {
        case activity, deals, invoices, tasks, info
        var id: String { rawValue }
        var title: String {
            switch self {
            case .activity: return "التواصل"
            case .deals: return "الصفقات"
            case .invoices: return "الفواتير"
            case .tasks: return "المهام"
            case .info: return "البيانات"
            }
        }
    }

    enum DetailSheet: String, Identifiable {
        case edit, interaction, task, deal, invoice
        var id: String { rawValue }
    }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            Section {
                contactActions
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                statsRow
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            Section {
                Picker("القسم", selection: $tab) {
                    ForEach(DetailTab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())

            switch tab {
            case .activity: activitySection
            case .deals: dealsSection
            case .invoices: invoicesSection
            case .tasks: tasksSection
            case .info: infoSection
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(customer.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button { sheet = .edit } label: { Label("تعديل البيانات", systemImage: "pencil") }
                    Button { customer.isFavorite.toggle() } label: {
                        Label(customer.isFavorite ? "إزالة من المفضلة" : "إضافة للمفضلة",
                              systemImage: customer.isFavorite ? "star.slash" : "star")
                    }
                    Divider()
                    Button { sheet = .interaction } label: { Label("تسجيل تواصل", systemImage: "text.bubble") }
                    Button { sheet = .task } label: { Label("مهمة جديدة", systemImage: "checklist") }
                    Button { sheet = .deal } label: { Label("صفقة جديدة", systemImage: "handshake") }
                    Button { sheet = .invoice } label: { Label("فاتورة جديدة", systemImage: "doc.badge.plus") }
                    Divider()
                    Button(role: .destructive) { confirmDelete = true } label: { Label("حذف العميل", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .edit: CustomerFormView(customer: customer)
                case .interaction: InteractionFormView(customer: customer)
                case .task: TaskFormView(customer: customer)
                case .deal: DealFormView(customer: customer)
                case .invoice: InvoiceFormView(customer: customer)
                }
            }
            .appEnvironment()
        }
        .sheet(item: $editingDeal) { deal in
            DealFormView(deal: deal).appEnvironment()
        }
        .sheet(item: $editingTask) { task in
            TaskFormView(task: task).appEnvironment()
        }
        .confirmationDialog("حذف العميل؟", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("حذف نهائياً", role: .destructive) { deleteCustomer() }
        } message: {
            Text("سيتم حذف العميل وكل فواتيره وصفقاته وسجل التواصل.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(name: customer.name, photoData: customer.photoData, size: 88, color: customer.status.color)
            VStack(spacing: 4) {
                Text(customer.name).font(.title2.bold())
                if !customer.company.isEmpty {
                    Text(customer.company).foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Menu {
                    ForEach(CustomerStatus.allCases) { status in
                        Button {
                            customer.status = status
                        } label: {
                            Label(status.title, systemImage: status.icon)
                        }
                    }
                } label: {
                    Badge(text: customer.status.title, color: customer.status.color, icon: customer.status.icon)
                }
                RatingView(rating: $customer.rating, size: .caption)
            }
            if !customer.tags.isEmpty {
                FlowLayout {
                    ForEach(customer.tags, id: \.self) { tag in
                        Text("#\(tag)").font(.caption).foregroundStyle(.tint)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var contactActions: some View {
        HStack(spacing: 10) {
            actionButton("اتصال", "phone.fill", .green, ContactActions.callURL(customer.phone), log: .call)
            actionButton("واتساب", "message.fill", .teal, ContactActions.whatsappURL(customer.whatsappNumber), log: .whatsapp)
            actionButton("رسالة", "text.bubble.fill", .blue, ContactActions.smsURL(customer.phone), log: nil)
            actionButton("بريد", "envelope.fill", .orange, ContactActions.emailURL(customer.email), log: .email)
            actionButton("خريطة", "map.fill", .red, ContactActions.mapsURL([customer.address, customer.city].filter { !$0.isEmpty }.joined(separator: " ")), log: nil)
        }
    }

    private func actionButton(_ title: String, _ icon: String, _ color: Color, _ url: URL?, log: InteractionType?) -> some View {
        Button {
            guard let url else { return }
            openURL(url)
            if let log { quickLog(log) }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.headline)
                    .frame(width: 44, height: 44)
                    .background((url == nil ? Color.gray : color).opacity(0.15), in: Circle())
                    .foregroundStyle(url == nil ? Color.gray : color)
                Text(title).font(.caption2).foregroundStyle(.primary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(url == nil)
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            miniStat("إجمالي المشتريات", Fmt.compactMoney(customer.totalInvoiced), .blue)
            miniStat("المدفوع", Fmt.compactMoney(customer.totalPaid), .green)
            miniStat("المستحق", Fmt.compactMoney(customer.balance), customer.balance > 0 ? .orange : .secondary)
        }
    }

    private func miniStat(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value).font(.headline).foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: Tabs

    @ViewBuilder
    private var activitySection: some View {
        Section {
            Button { sheet = .interaction } label: {
                Label("تسجيل تواصل جديد", systemImage: "plus.circle.fill")
            }
            if customer.interactionList.isEmpty {
                Text("لا يوجد سجل تواصل بعد").foregroundStyle(.secondary)
            }
            ForEach(customer.interactionList) { item in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: item.type.icon)
                        .foregroundStyle(item.type.color)
                        .frame(width: 32, height: 32)
                        .background(item.type.color.opacity(0.15), in: Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(item.type.title).font(.subheadline.bold())
                            Spacer()
                            Text(Fmt.dateTime(item.date)).font(.caption2).foregroundStyle(.secondary)
                        }
                        if !item.summary.isEmpty {
                            Text(item.summary).font(.subheadline)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        context.delete(item)
                    } label: {
                        Label("حذف", systemImage: "trash")
                    }
                }
            }
        } header: {
            Text("سجل التواصل")
        }
    }

    @ViewBuilder
    private var dealsSection: some View {
        Section {
            Button { sheet = .deal } label: { Label("صفقة جديدة", systemImage: "plus.circle.fill") }
            ForEach(customer.dealList.sorted { $0.createdAt > $1.createdAt }) { deal in
                Button { editingDeal = deal } label: { DealRow(deal: deal, showCustomer: false) }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button(role: .destructive) { context.delete(deal) } label: { Label("حذف", systemImage: "trash") }
                    }
            }
        } header: {
            Text("الصفقات")
        }
    }

    @ViewBuilder
    private var invoicesSection: some View {
        Section {
            Button { sheet = .invoice } label: { Label("فاتورة جديدة", systemImage: "plus.circle.fill") }
            ForEach(customer.invoiceList.sorted { $0.issueDate > $1.issueDate }) { invoice in
                NavigationLink {
                    InvoiceDetailView(invoice: invoice)
                } label: {
                    InvoiceRow(invoice: invoice, showCustomer: false)
                }
            }
        } header: {
            Text("الفواتير")
        }
    }

    @ViewBuilder
    private var tasksSection: some View {
        Section {
            Button { sheet = .task } label: { Label("مهمة جديدة", systemImage: "plus.circle.fill") }
            ForEach(customer.taskList.sorted { !$0.isDone && $1.isDone }) { task in
                TaskRow(task: task, showCustomer: false)
                    .contentShape(Rectangle())
                    .onTapGesture { editingTask = task }
                    .swipeActions {
                        Button(role: .destructive) {
                            NotificationManager.cancel(id: task.notificationID)
                            context.delete(task)
                        } label: { Label("حذف", systemImage: "trash") }
                    }
            }
        } header: {
            Text("المهام")
        }
    }

    @ViewBuilder
    private var infoSection: some View {
        Section("بيانات التواصل") {
            infoRow("الهاتف", customer.phone, icon: "phone")
            infoRow("واتساب", customer.whatsapp, icon: "message")
            infoRow("البريد", customer.email, icon: "envelope")
            infoRow("المدينة", customer.city, icon: "building.2")
            infoRow("العنوان", customer.address, icon: "mappin.and.ellipse")
        }
        Section("معلومات إضافية") {
            infoRow("المصدر", customer.source, icon: "arrow.down.right.circle")
            if let birthday = customer.birthday {
                infoRow("تاريخ الميلاد", Fmt.date(birthday), icon: "gift")
            }
            infoRow("عميل منذ", Fmt.date(customer.createdAt), icon: "calendar")
            if let last = customer.lastContactAt {
                infoRow("آخر تواصل", Fmt.relative(last), icon: "clock")
            }
            ForEach(customer.customFields) { field in
                infoRow(field.key, field.value, icon: "square.text.square")
            }
        }
        if !customer.notes.isEmpty {
            Section("ملاحظات") {
                Text(customer.notes)
            }
        }
        Section {
            Button { sheet = .edit } label: { Label("تعديل البيانات", systemImage: "pencil") }
        }
    }

    @ViewBuilder
    private func infoRow(_ title: String, _ value: String, icon: String) -> some View {
        if !value.isEmpty {
            LabeledContent {
                Text(value).textSelection(.enabled)
            } label: {
                Label(title, systemImage: icon)
            }
        }
    }

    // MARK: Actions

    private func quickLog(_ type: InteractionType) {
        let item = Interaction(type: type, summary: "")
        context.insert(item)
        item.customer = customer
        customer.lastContactAt = Date()
    }

    private func deleteCustomer() {
        let target = customer
        for task in target.taskList { NotificationManager.cancel(id: task.notificationID) }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            context.delete(target)
            try? context.save()
        }
    }
}
