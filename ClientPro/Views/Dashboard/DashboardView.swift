import SwiftUI
import SwiftData
import Charts

struct MonthAmount: Identifiable {
    let month: Date
    let kind: String
    let amount: Double
    var id: String { "\(month.timeIntervalSince1970)-\(kind)" }
}

struct DashboardView: View {
    @Environment(\.modelContext) private var context
    @Query private var customers: [Customer]
    @Query private var invoices: [Invoice]
    @Query private var payments: [Payment]
    @Query private var deals: [Deal]
    @Query(sort: \TaskItem.createdAt) private var tasks: [TaskItem]
    @Query private var expenses: [Expense]
    @Query private var products: [Product]
    @AppStorage(SettingsKey.businessName) private var businessName = ""
    @AppStorage(SettingsKey.monthlyTarget) private var monthlyTarget = 0.0

    @State private var quickSheet: QuickSheet?

    enum QuickSheet: String, Identifiable {
        case customer, invoice, task, deal, expense
        var id: String { rawValue }
    }

    private let calendar = Calendar.current

    // MARK: Metrics

    private var monthStart: Date { calendar.startOfMonth(for: Date()) }
    private var lastMonthStart: Date { calendar.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart }

    private var revenueThisMonth: Double {
        payments.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
    }

    private var revenueLastMonth: Double {
        payments.filter { $0.date >= lastMonthStart && $0.date < monthStart }.reduce(0) { $0 + $1.amount }
    }

    private var expensesThisMonth: Double {
        expenses.filter { $0.date >= monthStart }.reduce(0) { $0 + $1.amount }
    }

    private var outstanding: Double {
        invoices.filter { $0.status.isOutstanding }.reduce(0) { $0 + $1.balance }
    }

    private var overdueInvoices: [Invoice] {
        invoices.filter { $0.status == .overdue }.sorted { $0.dueDate < $1.dueDate }
    }

    private var openDeals: [Deal] { deals.filter { $0.stage.isOpen } }

    private var newCustomersThisMonth: Int {
        customers.filter { $0.createdAt >= monthStart }.count
    }

    private var focusTasks: [TaskItem] {
        tasks.filter { !$0.isDone && ($0.isOverdue || $0.isDueToday) }
            .sorted { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }
    }

    private var lowStock: [Product] { products.filter { $0.isActive && $0.isLowStock } }

    private var growthText: String? {
        guard revenueLastMonth > 0 else { return nil }
        let change = (revenueThisMonth - revenueLastMonth) / revenueLastMonth * 100
        let arrow = change >= 0 ? "▲" : "▼"
        return "\(arrow) \(Fmt.percent(abs(change))) عن الشهر الماضي"
    }

    private var chartData: [MonthAmount] {
        var result: [MonthAmount] = []
        for offset in (0..<6).reversed() {
            guard let start = calendar.date(byAdding: .month, value: -offset, to: monthStart),
                  let end = calendar.date(byAdding: .month, value: 1, to: start) else { continue }
            let revenue = payments.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
            let spent = expenses.filter { $0.date >= start && $0.date < end }.reduce(0) { $0 + $1.amount }
            result.append(MonthAmount(month: start, kind: "الإيرادات", amount: revenue))
            result.append(MonthAmount(month: start, kind: "المصروفات", amount: spent))
        }
        return result
    }

    private var stageTotals: [DealStage: Double] {
        var totals: [DealStage: Double] = [:]
        for deal in openDeals { totals[deal.stage, default: 0] += deal.value }
        return totals
    }

    struct StatusCount: Identifiable {
        let status: CustomerStatus
        let count: Int
        var id: String { status.rawValue }
    }

    private var statusCounts: [StatusCount] {
        CustomerStatus.allCases
            .map { status in StatusCount(status: status, count: customers.filter { $0.status == status }.count) }
            .filter { $0.count > 0 }
    }

    private var topCustomers: [Customer] {
        customers.filter { $0.totalPaid > 0 }.sorted { $0.totalPaid > $1.totalPaid }.prefix(5).map { $0 }
    }

    // MARK: Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    header
                    quickActions
                    kpiGrid
                    if monthlyTarget > 0 { targetCard }
                    revenueChart
                    if !focusTasks.isEmpty { tasksCard }
                    if !overdueInvoices.isEmpty { overdueCard }
                    pipelineCard
                    if !customers.isEmpty { customerStatusCard }
                    if !topCustomers.isEmpty { topCustomersCard }
                    if !lowStock.isEmpty { lowStockCard }
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("لوحة التحكم")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        ReportsView()
                    } label: {
                        Image(systemName: "chart.pie.fill")
                    }
                }
            }
            .sheet(item: $quickSheet) { sheet in
                Group {
                    switch sheet {
                    case .customer: CustomerFormView()
                    case .invoice: InvoiceFormView()
                    case .task: TaskFormView()
                    case .deal: DealFormView()
                    case .expense: ExpenseFormView()
                    }
                }
                .appEnvironment()
            }
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(greeting).font(.subheadline).foregroundStyle(.secondary)
                Text(businessName.isEmpty ? "نشاطي التجاري" : businessName)
                    .font(.title2.bold())
                Text(Date().formatted(.dateTime.weekday(.wide).day().month(.wide).locale(Fmt.locale)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var greeting: String {
        let hour = calendar.component(.hour, from: Date())
        return hour < 12 ? "صباح الخير ☀️" : "مساء الخير 🌙"
    }

    private var quickActions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                quickButton("عميل", "person.badge.plus", .blue, .customer)
                quickButton("فاتورة", "doc.badge.plus", .green, .invoice)
                quickButton("مهمة", "checklist", .orange, .task)
                quickButton("صفقة", "handshake.fill", .purple, .deal)
                quickButton("مصروف", "minus.circle.fill", .red, .expense)
            }
        }
    }

    private func quickButton(_ title: String, _ icon: String, _ color: Color, _ sheet: QuickSheet) -> some View {
        Button {
            quickSheet = sheet
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundStyle(color)
                    .frame(width: 48, height: 48)
                    .background(color.opacity(0.15), in: Circle())
                Text(title).font(.caption).foregroundStyle(.primary)
            }
            .frame(width: 70)
        }
        .buttonStyle(.plain)
    }

    private var kpiGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
            StatCard(title: "إيرادات الشهر", value: Fmt.compactMoney(revenueThisMonth),
                     icon: "arrow.down.circle.fill", color: .green, subtitle: growthText)
            StatCard(title: "صافي ربح الشهر", value: Fmt.compactMoney(revenueThisMonth - expensesThisMonth),
                     icon: "chart.line.uptrend.xyaxis", color: revenueThisMonth >= expensesThisMonth ? .teal : .red,
                     subtitle: "مصروفات \(Fmt.compactMoney(expensesThisMonth))")
            StatCard(title: "مستحقات لم تُحصّل", value: Fmt.compactMoney(outstanding),
                     icon: "hourglass", color: .orange,
                     subtitle: overdueInvoices.isEmpty ? nil : "\(Fmt.number(overdueInvoices.count)) فاتورة متأخرة")
            StatCard(title: "العملاء", value: Fmt.number(customers.count),
                     icon: "person.2.fill", color: .blue,
                     subtitle: newCustomersThisMonth > 0 ? "+\(Fmt.number(newCustomersThisMonth)) هذا الشهر" : nil)
            StatCard(title: "صفقات مفتوحة", value: Fmt.compactMoney(openDeals.reduce(0) { $0 + $1.value }),
                     icon: "handshake.fill", color: .purple,
                     subtitle: "\(Fmt.number(openDeals.count)) صفقة")
            StatCard(title: "مهام اليوم", value: Fmt.number(focusTasks.count),
                     icon: "checklist", color: .pink,
                     subtitle: tasks.filter(\.isOverdue).isEmpty ? nil : "\(Fmt.number(tasks.filter(\.isOverdue).count)) متأخرة")
        }
    }

    private var targetCard: some View {
        let progress = min(1, revenueThisMonth / max(monthlyTarget, 1))
        return DashboardCard(title: "هدف الشهر", icon: "target") {
            VStack(alignment: .leading, spacing: 8) {
                ProgressView(value: progress)
                    .tint(progress >= 1 ? Color.green : Color.accentColor)
                HStack {
                    Text("\(Fmt.money(revenueThisMonth)) من \(Fmt.money(monthlyTarget))")
                    Spacer()
                    Text(Fmt.percent(progress * 100)).bold()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var revenueChart: some View {
        DashboardCard(title: "الإيرادات والمصروفات (آخر ٦ شهور)", icon: "chart.bar.fill") {
            Chart(chartData) { item in
                BarMark(x: .value("الشهر", item.month, unit: .month),
                        y: .value("المبلغ", item.amount))
                    .foregroundStyle(by: .value("النوع", item.kind))
                    .position(by: .value("النوع", item.kind))
                    .cornerRadius(4)
            }
            .chartForegroundStyleScale(["الإيرادات": Color.green, "المصروفات": Color.red.opacity(0.7)])
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated), centered: true)
                }
            }
            .chartLegend(position: .top, alignment: .leading)
            .frame(height: 220)
        }
    }

    private var tasksCard: some View {
        DashboardCard(title: "مهام تحتاج انتباهك", icon: "bell.badge.fill") {
            VStack(spacing: 10) {
                ForEach(focusTasks.prefix(5)) { task in
                    TaskRow(task: task)
                    if task.id != focusTasks.prefix(5).last?.id { Divider() }
                }
            }
        }
    }

    private var overdueCard: some View {
        DashboardCard(title: "فواتير متأخرة السداد", icon: "exclamationmark.triangle.fill") {
            VStack(spacing: 10) {
                ForEach(overdueInvoices.prefix(5)) { invoice in
                    NavigationLink {
                        InvoiceDetailView(invoice: invoice)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(invoice.customer?.name ?? "بدون عميل").font(.subheadline.bold())
                                Text("\(invoice.number) • استحقت \(Fmt.relative(invoice.dueDate))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(Fmt.money(invoice.balance)).font(.subheadline.bold()).foregroundStyle(.red)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var pipelineCard: some View {
        DashboardCard(title: "مسار المبيعات", icon: "line.3.horizontal.decrease.circle.fill") {
            VStack(spacing: 10) {
                let totals = stageTotals
                let maxValue = max(1, totals.values.max() ?? 1)
                ForEach(DealStage.openStages) { stage in
                    let count = openDeals.filter { $0.stage == stage }.count
                    let value = totals[stage] ?? 0
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label(stage.title, systemImage: stage.icon).font(.caption).foregroundStyle(stage.color)
                            Spacer()
                            Text("\(Fmt.number(count)) • \(Fmt.compactMoney(value))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Color(.tertiarySystemFill))
                                Capsule().fill(stage.color)
                                    .frame(width: max(4, geo.size.width * value / maxValue))
                            }
                        }
                        .frame(height: 8)
                    }
                }
                NavigationLink {
                    DealsView()
                } label: {
                    Text("عرض كل الصفقات").font(.subheadline.bold()).frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
        }
    }

    private var customerStatusCard: some View {
        DashboardCard(title: "توزيع العملاء", icon: "person.3.fill") {
            let counts = statusCounts
            HStack(spacing: 16) {
                Chart(counts) { item in
                    SectorMark(angle: .value("العدد", item.count), innerRadius: .ratio(0.6), angularInset: 2)
                        .foregroundStyle(item.status.color)
                        .cornerRadius(3)
                }
                .frame(width: 120, height: 120)
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(counts) { item in
                        HStack(spacing: 6) {
                            Circle().fill(item.status.color).frame(width: 8, height: 8)
                            Text(item.status.title).font(.caption)
                            Spacer()
                            Text(Fmt.number(item.count)).font(.caption.bold())
                        }
                    }
                }
            }
        }
    }

    private var topCustomersCard: some View {
        DashboardCard(title: "أفضل العملاء", icon: "star.fill") {
            VStack(spacing: 10) {
                ForEach(Array(topCustomers.enumerated()), id: \.element.id) { index, customer in
                    NavigationLink {
                        CustomerDetailView(customer: customer)
                    } label: {
                        HStack(spacing: 10) {
                            Text(Fmt.number(index + 1)).font(.caption.bold()).foregroundStyle(.secondary).frame(width: 18)
                            AvatarView(name: customer.name, photoData: customer.photoData, size: 34, color: customer.status.color)
                            Text(customer.name).font(.subheadline)
                            Spacer()
                            Text(Fmt.money(customer.totalPaid)).font(.subheadline.bold())
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var lowStockCard: some View {
        DashboardCard(title: "مخزون منخفض", icon: "shippingbox.fill") {
            VStack(spacing: 8) {
                ForEach(lowStock) { product in
                    HStack {
                        Text(product.name).font(.subheadline)
                        Spacer()
                        Badge(text: "متبقي \(Fmt.number(product.stock))", color: product.stock <= 0 ? .red : .orange)
                    }
                }
            }
        }
    }
}
