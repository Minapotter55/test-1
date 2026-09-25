import Foundation
import SwiftData

/// A free-form field the business owner adds per customer (e.g. "رقم السجل", "المقاس").
struct CustomField: Codable, Identifiable, Hashable {
    var id = UUID()
    var key: String
    var value: String
}

@Model
final class Customer {
    var name: String = ""
    var company: String = ""
    var phone: String = ""
    var whatsapp: String = ""
    var email: String = ""
    var address: String = ""
    var city: String = ""
    var notes: String = ""
    var source: String = ""
    var tags: [String] = []
    var statusRaw: String = CustomerStatus.lead.rawValue
    var rating: Int = 0
    var isFavorite: Bool = false
    var createdAt: Date = Date()
    var lastContactAt: Date?
    var birthday: Date?
    @Attribute(.externalStorage) var photoData: Data?
    var customFieldsData: Data?

    @Relationship(deleteRule: .cascade, inverse: \Deal.customer)
    var deals: [Deal]? = []

    @Relationship(deleteRule: .cascade, inverse: \Invoice.customer)
    var invoices: [Invoice]? = []

    @Relationship(deleteRule: .nullify, inverse: \TaskItem.customer)
    var tasks: [TaskItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \Interaction.customer)
    var interactions: [Interaction]? = []

    init(name: String, phone: String = "", company: String = "", status: CustomerStatus = .lead) {
        self.name = name
        self.phone = phone
        self.company = company
        self.statusRaw = status.rawValue
        self.createdAt = Date()
    }

    var status: CustomerStatus {
        get { CustomerStatus(rawValue: statusRaw) ?? .lead }
        set { statusRaw = newValue.rawValue }
    }

    var customFields: [CustomField] {
        get {
            guard let customFieldsData else { return [] }
            return (try? JSONDecoder().decode([CustomField].self, from: customFieldsData)) ?? []
        }
        set { customFieldsData = try? JSONEncoder().encode(newValue) }
    }

    /// WhatsApp number falls back to the phone number.
    var whatsappNumber: String { whatsapp.isEmpty ? phone : whatsapp }

    var invoiceList: [Invoice] { invoices ?? [] }
    var dealList: [Deal] { deals ?? [] }
    var taskList: [TaskItem] { tasks ?? [] }
    var interactionList: [Interaction] { (interactions ?? []).sorted { $0.date > $1.date } }

    var totalInvoiced: Double {
        invoiceList.filter { $0.state == .issued }.reduce(0) { $0 + $1.total }
    }

    var totalPaid: Double {
        invoiceList.filter { $0.state == .issued }.reduce(0) { $0 + $1.paidAmount }
    }

    var balance: Double {
        invoiceList.filter { $0.status.isOutstanding }.reduce(0) { $0 + $1.balance }
    }

    var openDealsValue: Double {
        dealList.filter { $0.stage.isOpen }.reduce(0) { $0 + $1.value }
    }

    var openTasksCount: Int { taskList.filter { !$0.isDone }.count }
}
