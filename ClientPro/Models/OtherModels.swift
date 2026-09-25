import Foundation
import SwiftData

@Model
final class Product {
    var name: String = ""
    var sku: String = ""
    var category: String = ""
    var price: Double = 0
    var cost: Double = 0
    var stock: Int = 0
    var trackStock: Bool = false
    var lowStockThreshold: Int = 5
    var isService: Bool = false
    var isActive: Bool = true
    var notes: String = ""
    var createdAt: Date = Date()

    init(name: String, price: Double, isService: Bool = false) {
        self.name = name
        self.price = price
        self.isService = isService
        self.createdAt = Date()
    }

    var isLowStock: Bool { trackStock && stock <= lowStockThreshold }
    var margin: Double { price - cost }
    var marginPercent: Double { price > 0 ? (price - cost) / price * 100 : 0 }
}

@Model
final class TaskItem {
    var title: String = ""
    var notes: String = ""
    var dueDate: Date?
    var isDone: Bool = false
    var completedAt: Date?
    var priorityRaw: String = TaskPriority.medium.rawValue
    var reminderEnabled: Bool = false
    var notificationID: String = UUID().uuidString
    var createdAt: Date = Date()
    var customer: Customer?

    init(title: String, dueDate: Date? = nil, priority: TaskPriority = .medium) {
        self.title = title
        self.dueDate = dueDate
        self.priorityRaw = priority.rawValue
        self.notificationID = UUID().uuidString
        self.createdAt = Date()
    }

    var priority: TaskPriority {
        get { TaskPriority(rawValue: priorityRaw) ?? .medium }
        set { priorityRaw = newValue.rawValue }
    }

    var isOverdue: Bool {
        guard !isDone, let dueDate else { return false }
        return dueDate < Date()
    }

    var isDueToday: Bool {
        guard let dueDate else { return false }
        return Calendar.current.isDateInToday(dueDate)
    }
}

@Model
final class Interaction {
    var typeRaw: String = InteractionType.note.rawValue
    var summary: String = ""
    var date: Date = Date()
    var customer: Customer?

    init(type: InteractionType, summary: String, date: Date = Date()) {
        self.typeRaw = type.rawValue
        self.summary = summary
        self.date = date
    }

    var type: InteractionType {
        get { InteractionType(rawValue: typeRaw) ?? .note }
        set { typeRaw = newValue.rawValue }
    }
}

@Model
final class Expense {
    var title: String = ""
    var amount: Double = 0
    var date: Date = Date()
    var categoryRaw: String = ExpenseCategory.other.rawValue
    var notes: String = ""
    var createdAt: Date = Date()

    init(title: String, amount: Double, category: ExpenseCategory, date: Date = Date()) {
        self.title = title
        self.amount = amount
        self.categoryRaw = category.rawValue
        self.date = date
        self.createdAt = Date()
    }

    var category: ExpenseCategory {
        get { ExpenseCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }
}
