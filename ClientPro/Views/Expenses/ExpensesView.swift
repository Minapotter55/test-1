import SwiftUI
import SwiftData

struct ExpensesView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Expense.date, order: .reverse) private var expenses: [Expense]

    @State private var category: ExpenseCategory?
    @State private var showForm = false
    @State private var editing: Expense?
    @State private var shareItem: ShareItem?

    private var filtered: [Expense] {
        guard let category else { return expenses }
        return expenses.filter { $0.category == category }
    }

    private var byMonth: [(Date, [Expense])] {
        let cal = Calendar.current
        let dict = Dictionary(grouping: filtered) { cal.startOfMonth(for: $0.date) }
        return dict.keys.sorted(by: >).map { ($0, dict[$0] ?? []) }
    }

    var body: some View {
        List {
            if !expenses.isEmpty {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            FilterChip(title: "الكل", isSelected: category == nil) { category = nil }
                            ForEach(ExpenseCategory.allCases) { c in
                                if expenses.contains(where: { $0.category == c }) {
                                    FilterChip(title: c.title, color: c.color, isSelected: category == c) {
                                        category = category == c ? nil : c
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ForEach(byMonth, id: \.0) { group in
                let month = group.0
                let items = group.1
                Section {
                    ForEach(items) { expense in
                        Button { editing = expense } label: { ExpenseRow(expense: expense) }
                            .buttonStyle(.plain)
                            .swipeActions {
                                Button(role: .destructive) { context.delete(expense) } label: { Label("حذف", systemImage: "trash") }
                            }
                    }
                } header: {
                    HStack {
                        Text(Fmt.month(month))
                        Spacer()
                        Text(Fmt.money(items.reduce(0) { $0 + $1.amount })).foregroundStyle(.red)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .overlay {
            if expenses.isEmpty {
                ContentUnavailableView {
                    Label("لا توجد مصروفات", systemImage: "creditcard")
                } description: {
                    Text("سجّل مصروفاتك لتعرف صافي أرباحك الحقيقي")
                } actions: {
                    Button("إضافة مصروف") { showForm = true }.buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("المصروفات")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if let url = CSVExporter.expenses(filtered) { shareItem = ShareItem(url: url) }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(expenses.isEmpty)
            }
        }
        .sheet(isPresented: $showForm) { ExpenseFormView().appEnvironment() }
        .sheet(item: $editing) { ExpenseFormView(expense: $0).appEnvironment() }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
    }
}

struct ExpenseRow: View {
    let expense: Expense

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: expense.category.icon)
                .foregroundStyle(expense.category.color)
                .frame(width: 36, height: 36)
                .background(expense.category.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(expense.title).font(.subheadline.bold())
                Text("\(expense.category.title) • \(Fmt.date(expense.date))").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(Fmt.money(expense.amount)).font(.subheadline.bold()).foregroundStyle(.red)
        }
        .contentShape(Rectangle())
    }
}

struct ExpenseFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let expense: Expense?

    @State private var title: String
    @State private var amount: Double
    @State private var date: Date
    @State private var category: ExpenseCategory
    @State private var notes: String

    init(expense: Expense? = nil) {
        self.expense = expense
        _title = State(initialValue: expense?.title ?? "")
        _amount = State(initialValue: expense?.amount ?? 0)
        _date = State(initialValue: expense?.date ?? Date())
        _category = State(initialValue: expense?.category ?? .other)
        _notes = State(initialValue: expense?.notes ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("البند *", text: $title)
                    LabeledContent("المبلغ") {
                        AmountField("0", value: $amount).multilineTextAlignment(.trailing)
                    }
                    Picker("التصنيف", selection: $category) {
                        ForEach(ExpenseCategory.allCases) { c in
                            Label(c.title, systemImage: c.icon).tag(c)
                        }
                    }
                    DatePicker("التاريخ", selection: $date, displayedComponents: .date)
                }
                Section("ملاحظات") {
                    TextField("اختياري", text: $notes, axis: .vertical)
                }
            }
            .navigationTitle(expense == nil ? "مصروف جديد" : "تعديل المصروف")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || amount <= 0)
                }
            }
        }
    }

    private func save() {
        let target: Expense
        if let expense {
            target = expense
        } else {
            target = Expense(title: title, amount: amount, category: category, date: date)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.amount = amount
        target.category = category
        target.date = date
        target.notes = notes
        try? context.save()
        dismiss()
    }
}
