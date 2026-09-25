import SwiftUI
import SwiftData
import Charts

struct ReportsView: View {
    @Query private var customers: [Customer]
    @Query private var invoices: [Invoice]
    @Query private var payments: [Payment]
    @Query private var deals: [Deal]
    @Query private var expenses: [Expense]

    @State private var period: Period = .thisMonth

    enum Period: String, CaseIterable, Identifiable {
        case thisMonth, lastMonth, last3Months, thisYear, all
        var id: String { rawValue }
        var title: String {
            switch self {
            case .thisMonth: return "هذا الشهر"
            case .lastMonth: return "الشهر الماضي"
            case .last3Months: return "آخر ٣ شهور"
            case .thisYear: return "هذا العام"
            case .all: return "الكل"
            }
        }

        var range: ClosedRange<Date> {
            let cal = Calendar.current
            let now = Date()
            let monthStart = cal.startOfMonth(for: now)
            switch self {
            case .thisMonth:
                return monthStart...now
            case .lastMonth:
                let start = cal.date(byAdding: .month, value: -1, to: monthStart) ?? monthStart
                return start...monthStart.addingTimeInterval(-1)
            case .last3Months:
                return (cal.date(byAdding: .month, value: -2, to: monthStart) ?? monthStart)...now
            case .thisYear:
                let start = cal.date(from: cal.dateComponents([.year], from: now)) ?? monthStart
                return start...now
            case .all:
                return Date.distantPast...now
            }
        }
    }

    // MARK: Numbers for the selected period

    private var range: ClosedRange<Date> { period.range }
    private var periodPayments: [Payment] { payments.filter { range.contains($0.date) } }
    private var periodExpenses: [Expense] { expenses.filter { range.contains($0.date) } }
    private var periodInvoices: [Invoice] { invoices.filter { $0.state == .issued && range.contains($0.issueDate) } }

    private var revenue: Double { periodPayments.reduce(0) { $0 + $1.amount } }
    private var spent: Double { periodExpenses.reduce(0) { $0 + $1.amount } }
    private var profit: Double { revenue - spent }
    private var sales: Double { periodInvoices.reduce(0) { $0 + $1.total } }
    private var averageInvoice: Double { periodInvoices.isEmpty ? 0 : sales / Double(periodInvoices.count) }
    private var newCustomers: Int { customers.filter { range.contains($0.createdAt) }.count }

    private var closedDeals: [Deal] { deals.filter { !$0.stage.isOpen && range.contains($0.closedAt ?? .distantPast) } }
    private var winRate: Double {
        guard !closedDeals.isEmpty else { return 0 }
        return Double(closedDeals.filter { $0.stage == .won }.count) / Double(closedDeals.count) * 100
    }

    private struct Slice: Identifiable {
        let name: String
        let value: Double
        let color: Color
        var id: String { name }
    }

    private var expenseSlices: [Slice] {
        ExpenseCategory.allCases.compactMap { c in
            let total = periodExpenses.filter { $0.category == c }.reduce(0) { $0 + $1.amount }
            return total > 0 ? Slice(name: c.title, value: total, color: c.color) : nil
        }
        .sorted { $0.value > $1.value }
    }

    private var topCustomers: [Slice] {
        var totals: [String: Double] = [:]
        for p in periodPayments {
            let name = p.invoice?.customer?.name ?? "بدون عميل"
            totals[name, default: 0] += p.amount
        }
        return totals.sorted { $0.value > $1.value }.prefix(6).map { Slice(name: $0.key, value: $0.value, color: .accentColor) }
    }

    private var topItems: [Slice] {
        var totals: [String: Double] = [:]
        for invoice in periodInvoices {
            for item in invoice.items ?? [] { totals[item.name, default: 0] += item.total }
        }
        return totals.sorted { $0.value > $1.value }.prefix(6).map { Slice(name: $0.key, value: $0.value, color: .purple) }
    }

    private var sourceSlices: [Slice] {
        let palette: [Color] = [.blue, .green, .orange, .purple, .pink, .teal, .indigo, .brown]
        let dict = Dictionary(grouping: customers.filter { range.contains($0.createdAt) }) { $0.source.isEmpty ? "غير محدد" : $0.source }
        return dict.sorted { $0.value.count > $1.value.count }.enumerated().map { index, entry in
            Slice(name: entry.key, value: Double(entry.value.count), color: palette[index % palette.count])
        }
    }

    // MARK: Body

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("الفترة", selection: $period) {
                    ForEach(Period.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)

                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    StatCard(title: "المحصّل", value: Fmt.compactMoney(revenue), icon: "arrow.down.circle.fill", color: .green)
                    StatCard(title: "المصروفات", value: Fmt.compactMoney(spent), icon: "arrow.up.circle.fill", color: .red)
                    StatCard(title: "صافي الربح", value: Fmt.compactMoney(profit), icon: "chart.line.uptrend.xyaxis",
                             color: profit >= 0 ? .teal : .red,
                             subtitle: revenue > 0 ? "هامش \(Fmt.percent(profit / revenue * 100))" : nil)
                    StatCard(title: "المبيعات (فواتير)", value: Fmt.compactMoney(sales), icon: "doc.text.fill", color: .blue,
                             subtitle: "\(Fmt.number(periodInvoices.count)) فاتورة")
                    StatCard(title: "متوسط الفاتورة", value: Fmt.compactMoney(averageInvoice), icon: "divide.circle.fill", color: .orange)
                    StatCard(title: "عملاء جدد", value: Fmt.number(newCustomers), icon: "person.badge.plus", color: .purple,
                             subtitle: closedDeals.isEmpty ? nil : "نجاح الصفقات \(Fmt.percent(winRate))")
                }

                if !topCustomers.isEmpty {
                    DashboardCard(title: "أعلى العملاء تحصيلاً", icon: "person.crop.circle.badge.checkmark") {
                        barChart(topCustomers)
                    }
                }

                if !topItems.isEmpty {
                    DashboardCard(title: "أكثر المنتجات/الخدمات مبيعاً", icon: "shippingbox.fill") {
                        barChart(topItems)
                    }
                }

                if !expenseSlices.isEmpty {
                    DashboardCard(title: "توزيع المصروفات", icon: "chart.pie.fill") {
                        pieChart(expenseSlices)
                    }
                }

                if !sourceSlices.isEmpty {
                    DashboardCard(title: "مصادر العملاء الجدد", icon: "arrow.down.right.circle.fill") {
                        pieChart(sourceSlices)
                    }
                }
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("التقارير")
    }

    private func barChart(_ data: [Slice]) -> some View {
        Chart(data) { slice in
            BarMark(x: .value("القيمة", slice.value), y: .value("الاسم", slice.name))
                .foregroundStyle(slice.color.gradient)
                .cornerRadius(4)
                .annotation(position: .trailing) {
                    Text(Fmt.compactMoney(slice.value)).font(.caption2).foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .frame(height: CGFloat(data.count) * 36 + 20)
    }

    private func pieChart(_ data: [Slice]) -> some View {
        let total = data.reduce(0) { $0 + $1.value }
        return HStack(spacing: 16) {
            Chart(data) { slice in
                SectorMark(angle: .value("القيمة", slice.value), innerRadius: .ratio(0.55), angularInset: 2)
                    .foregroundStyle(slice.color)
                    .cornerRadius(3)
            }
            .frame(width: 130, height: 130)
            VStack(alignment: .leading, spacing: 6) {
                ForEach(data) { slice in
                    HStack(spacing: 6) {
                        Circle().fill(slice.color).frame(width: 8, height: 8)
                        Text(slice.name).font(.caption).lineLimit(1)
                        Spacer()
                        Text(Fmt.percent(total > 0 ? slice.value / total * 100 : 0)).font(.caption.bold())
                    }
                }
            }
        }
    }
}
