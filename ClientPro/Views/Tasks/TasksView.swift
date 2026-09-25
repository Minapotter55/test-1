import SwiftUI
import SwiftData

struct TasksView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \TaskItem.createdAt, order: .reverse) private var tasks: [TaskItem]

    @State private var showForm = false
    @State private var editingTask: TaskItem?
    @State private var showCompleted = false
    @State private var search = ""

    private func byDue(_ a: TaskItem, _ b: TaskItem) -> Bool {
        let da = a.dueDate ?? .distantFuture
        let db = b.dueDate ?? .distantFuture
        if da != db { return da < db }
        return a.priority.rank > b.priority.rank
    }

    private var matching: [TaskItem] {
        let q = search.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return tasks }
        return tasks.filter {
            $0.title.localizedCaseInsensitiveContains(q) || ($0.customer?.name.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    private var openTasks: [TaskItem] { matching.filter { !$0.isDone } }
    private var overdue: [TaskItem] { openTasks.filter { $0.isOverdue }.sorted(by: byDue) }
    private var today: [TaskItem] { openTasks.filter { $0.isDueToday && !$0.isOverdue }.sorted(by: byDue) }
    private var upcoming: [TaskItem] {
        openTasks.filter { t in
            guard let due = t.dueDate else { return false }
            return !Calendar.current.isDateInToday(due) && due > Date()
        }.sorted(by: byDue)
    }
    private var noDate: [TaskItem] { openTasks.filter { $0.dueDate == nil }.sorted { $0.priority.rank > $1.priority.rank } }
    private var completed: [TaskItem] {
        matching.filter { $0.isDone }.sorted { ($0.completedAt ?? .distantPast) > ($1.completedAt ?? .distantPast) }
    }

    var body: some View {
        NavigationStack {
            List {
                taskSection("متأخرة", overdue, color: .red)
                taskSection("اليوم", today, color: .orange)
                taskSection("قادمة", upcoming, color: .blue)
                taskSection("بدون موعد", noDate, color: .gray)
                if !completed.isEmpty {
                    Section {
                        DisclosureGroup(isExpanded: $showCompleted) {
                            ForEach(completed.prefix(50)) { task in row(task) }
                        } label: {
                            Text("المكتملة (\(Fmt.number(completed.count)))")
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if tasks.isEmpty {
                    ContentUnavailableView {
                        Label("لا توجد مهام", systemImage: "checklist")
                    } description: {
                        Text("أضف مهام المتابعة مع العملاء وسيذكّرك التطبيق في موعدها")
                    } actions: {
                        Button("مهمة جديدة") { showForm = true }.buttonStyle(.borderedProminent)
                    }
                } else if openTasks.isEmpty && completed.isEmpty {
                    ContentUnavailableView.search(text: search)
                } else if openTasks.isEmpty && search.isEmpty {
                    ContentUnavailableView("أحسنت! 🎉", systemImage: "checkmark.circle", description: Text("لا توجد مهام مفتوحة"))
                }
            }
            .navigationTitle("المهام")
            .searchable(text: $search, prompt: "ابحث في المهام")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showForm = true } label: { Image(systemName: "plus.circle.fill").font(.title3) }
                }
            }
            .sheet(isPresented: $showForm) { TaskFormView().appEnvironment() }
            .sheet(item: $editingTask) { TaskFormView(task: $0).appEnvironment() }
        }
    }

    @ViewBuilder
    private func taskSection(_ title: String, _ list: [TaskItem], color: Color) -> some View {
        if !list.isEmpty {
            Section {
                ForEach(list) { task in row(task) }
            } header: {
                HStack {
                    Circle().fill(color).frame(width: 8, height: 8)
                    Text("\(title) (\(Fmt.number(list.count)))")
                }
            }
        }
    }

    private func row(_ task: TaskItem) -> some View {
        TaskRow(task: task)
            .contentShape(Rectangle())
            .onTapGesture { editingTask = task }
            .swipeActions {
                Button(role: .destructive) {
                    NotificationManager.cancel(id: task.notificationID)
                    context.delete(task)
                } label: {
                    Label("حذف", systemImage: "trash")
                }
            }
            .swipeActions(edge: .leading) {
                if !task.isDone, let due = task.dueDate {
                    Button {
                        task.dueDate = Calendar.current.date(byAdding: .day, value: 1, to: max(due, Date()))
                        NotificationManager.schedule(for: task)
                    } label: {
                        Label("تأجيل يوم", systemImage: "arrow.uturn.forward")
                    }
                    .tint(.orange)
                }
            }
    }
}

struct TaskRow: View {
    @Bindable var task: TaskItem
    var showCustomer = true

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button {
                withAnimation {
                    task.isDone.toggle()
                    task.completedAt = task.isDone ? Date() : nil
                    if task.isDone {
                        NotificationManager.cancel(id: task.notificationID)
                    } else {
                        NotificationManager.schedule(for: task)
                    }
                }
            } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(task.isDone ? Color.green : task.priority.color)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .font(.subheadline.weight(.medium))
                    .strikethrough(task.isDone)
                    .foregroundStyle(task.isDone ? Color.secondary : Color.primary)
                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        Label(Fmt.dateTime(due), systemImage: "calendar")
                            .foregroundStyle(task.isOverdue ? Color.red : Color.secondary)
                    }
                    if showCustomer, let customer = task.customer {
                        Label(customer.name, systemImage: "person")
                            .foregroundStyle(.secondary)
                    }
                    if task.reminderEnabled && !task.isDone {
                        Image(systemName: "bell.fill").foregroundStyle(.orange)
                    }
                }
                .font(.caption)
                .lineLimit(1)
            }
            Spacer()
            if task.priority == .high && !task.isDone {
                Image(systemName: "flag.fill").font(.caption).foregroundStyle(.red)
            }
        }
    }
}

struct TaskFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query(sort: \Customer.name) private var customers: [Customer]

    let task: TaskItem?

    @State private var title: String
    @State private var notes: String
    @State private var hasDueDate: Bool
    @State private var dueDate: Date
    @State private var priority: TaskPriority
    @State private var reminder: Bool
    @State private var customer: Customer?

    init(task: TaskItem? = nil, customer: Customer? = nil) {
        self.task = task
        let defaultDue = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0,
                                               of: Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()) ?? Date()
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _hasDueDate = State(initialValue: task == nil ? true : task?.dueDate != nil)
        _dueDate = State(initialValue: task?.dueDate ?? defaultDue)
        _priority = State(initialValue: task?.priority ?? .medium)
        _reminder = State(initialValue: task?.reminderEnabled ?? true)
        _customer = State(initialValue: task?.customer ?? customer)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("عنوان المهمة *", text: $title)
                    TextField("تفاصيل (اختياري)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Picker("العميل", selection: $customer) {
                        Text("بدون عميل").tag(Customer?.none)
                        ForEach(customers) { c in Text(c.name).tag(Customer?.some(c)) }
                    }
                    Picker("الأولوية", selection: $priority) {
                        ForEach(TaskPriority.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("موعد محدد", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("الموعد", selection: $dueDate)
                        Toggle("تذكير بإشعار", isOn: $reminder)
                        HStack {
                            quickDate("بعد ساعة", Date().addingTimeInterval(3600))
                            quickDate("غداً", Calendar.current.date(byAdding: .day, value: 1, to: dueDate) ?? dueDate)
                            quickDate("بعد أسبوع", Calendar.current.date(byAdding: .day, value: 7, to: Date()) ?? Date())
                        }
                    }
                }
            }
            .navigationTitle(task == nil ? "مهمة جديدة" : "تعديل المهمة")
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

    private func quickDate(_ title: String, _ date: Date) -> some View {
        Button(title) { dueDate = date }
            .buttonStyle(.bordered)
            .font(.caption)
            .frame(maxWidth: .infinity)
    }

    private func save() {
        let target: TaskItem
        if let task {
            target = task
        } else {
            target = TaskItem(title: title)
            context.insert(target)
        }
        target.title = title.trimmingCharacters(in: .whitespaces)
        target.notes = notes
        target.dueDate = hasDueDate ? dueDate : nil
        target.priority = priority
        target.reminderEnabled = hasDueDate && reminder
        target.customer = customer
        if target.reminderEnabled { NotificationManager.requestAuthorization() }
        NotificationManager.schedule(for: target)
        try? context.save()
        dismiss()
    }
}
