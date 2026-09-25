import Foundation
import SwiftData

@Model
final class Invoice {
    var number: String = ""
    var issueDate: Date = Date()
    var dueDate: Date = Date()
    var stateRaw: String = InvoiceState.issued.rawValue
    /// Fixed discount amount, applied before tax.
    var discount: Double = 0
    /// Tax percentage, e.g. 14 for 14%.
    var taxRate: Double = 0
    var notes: String = ""
    var createdAt: Date = Date()
    var customer: Customer?

    @Relationship(deleteRule: .cascade, inverse: \InvoiceItem.invoice)
    var items: [InvoiceItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Payment.invoice)
    var payments: [Payment]? = []

    init(number: String, issueDate: Date = Date(), dueDate: Date = Date()) {
        self.number = number
        self.issueDate = issueDate
        self.dueDate = dueDate
        self.createdAt = Date()
    }

    var state: InvoiceState {
        get { InvoiceState(rawValue: stateRaw) ?? .issued }
        set { stateRaw = newValue.rawValue }
    }

    var sortedItems: [InvoiceItem] { (items ?? []).sorted { $0.sortIndex < $1.sortIndex } }
    var sortedPayments: [Payment] { (payments ?? []).sorted { $0.date > $1.date } }

    var subtotal: Double { (items ?? []).reduce(0) { $0 + $1.total } }
    var taxableAmount: Double { max(0, subtotal - discount) }
    var taxAmount: Double { taxableAmount * taxRate / 100 }
    var total: Double { taxableAmount + taxAmount }
    var paidAmount: Double { (payments ?? []).reduce(0) { $0 + $1.amount } }
    var balance: Double { max(0, total - paidAmount) }

    var status: InvoiceStatus {
        switch state {
        case .draft: return .draft
        case .cancelled: return .cancelled
        case .issued:
            if balance <= 0.009 { return .paid }
            if dueDate < Calendar.current.startOfDay(for: Date()) { return .overdue }
            if paidAmount > 0 { return .partial }
            return .unpaid
        }
    }
}

@Model
final class InvoiceItem {
    var name: String = ""
    var quantity: Double = 1
    var unitPrice: Double = 0
    var sortIndex: Int = 0
    var invoice: Invoice?

    init(name: String, quantity: Double, unitPrice: Double, sortIndex: Int) {
        self.name = name
        self.quantity = quantity
        self.unitPrice = unitPrice
        self.sortIndex = sortIndex
    }

    var total: Double { quantity * unitPrice }
}

@Model
final class Payment {
    var amount: Double = 0
    var date: Date = Date()
    var methodRaw: String = PaymentMethod.cash.rawValue
    var note: String = ""
    var invoice: Invoice?

    init(amount: Double, date: Date = Date(), method: PaymentMethod = .cash, note: String = "") {
        self.amount = amount
        self.date = date
        self.methodRaw = method.rawValue
        self.note = note
    }

    var method: PaymentMethod {
        get { PaymentMethod(rawValue: methodRaw) ?? .cash }
        set { methodRaw = newValue.rawValue }
    }
}
