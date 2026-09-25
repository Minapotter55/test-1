import SwiftUI

// MARK: - Customer status

enum CustomerStatus: String, CaseIterable, Identifiable, Codable {
    case lead, prospect, active, vip, inactive

    var id: String { rawValue }

    var title: String {
        switch self {
        case .lead: return "عميل محتمل"
        case .prospect: return "مهتم"
        case .active: return "نشط"
        case .vip: return "VIP"
        case .inactive: return "غير نشط"
        }
    }

    var color: Color {
        switch self {
        case .lead: return .blue
        case .prospect: return .orange
        case .active: return .green
        case .vip: return .purple
        case .inactive: return .gray
        }
    }

    var icon: String {
        switch self {
        case .lead: return "person.crop.circle.badge.questionmark"
        case .prospect: return "sparkles"
        case .active: return "checkmark.seal.fill"
        case .vip: return "crown.fill"
        case .inactive: return "moon.zzz.fill"
        }
    }
}

// MARK: - Deal stage

enum DealStage: String, CaseIterable, Identifiable, Codable {
    case new, contacted, proposal, negotiation, won, lost

    var id: String { rawValue }

    var title: String {
        switch self {
        case .new: return "جديدة"
        case .contacted: return "تم التواصل"
        case .proposal: return "عرض سعر"
        case .negotiation: return "تفاوض"
        case .won: return "مكسب"
        case .lost: return "خسارة"
        }
    }

    var color: Color {
        switch self {
        case .new: return .blue
        case .contacted: return .teal
        case .proposal: return .orange
        case .negotiation: return .purple
        case .won: return .green
        case .lost: return .red
        }
    }

    var icon: String {
        switch self {
        case .new: return "sparkle"
        case .contacted: return "phone.fill"
        case .proposal: return "doc.text.fill"
        case .negotiation: return "arrow.left.arrow.right"
        case .won: return "trophy.fill"
        case .lost: return "xmark.circle.fill"
        }
    }

    var defaultProbability: Int {
        switch self {
        case .new: return 10
        case .contacted: return 25
        case .proposal: return 50
        case .negotiation: return 75
        case .won: return 100
        case .lost: return 0
        }
    }

    var isOpen: Bool { self != .won && self != .lost }

    static var openStages: [DealStage] { allCases.filter { $0.isOpen } }
}

// MARK: - Invoice

/// What the user explicitly set on the invoice.
enum InvoiceState: String, Codable {
    case draft, issued, cancelled
}

/// What the invoice looks like right now (derived from state, payments and due date).
enum InvoiceStatus: String, CaseIterable, Identifiable {
    case draft, unpaid, partial, overdue, paid, cancelled

    var id: String { rawValue }

    var title: String {
        switch self {
        case .draft: return "مسودة"
        case .unpaid: return "غير مدفوعة"
        case .partial: return "مدفوعة جزئياً"
        case .overdue: return "متأخرة"
        case .paid: return "مدفوعة"
        case .cancelled: return "ملغاة"
        }
    }

    var color: Color {
        switch self {
        case .draft: return .gray
        case .unpaid: return .orange
        case .partial: return .yellow
        case .overdue: return .red
        case .paid: return .green
        case .cancelled: return .secondary
        }
    }

    var icon: String {
        switch self {
        case .draft: return "pencil.circle"
        case .unpaid: return "clock"
        case .partial: return "circle.lefthalf.filled"
        case .overdue: return "exclamationmark.triangle.fill"
        case .paid: return "checkmark.circle.fill"
        case .cancelled: return "xmark.circle"
        }
    }

    /// Counts towards what customers owe.
    var isOutstanding: Bool { self == .unpaid || self == .partial || self == .overdue }
}

enum PaymentMethod: String, CaseIterable, Identifiable, Codable {
    case cash, bank, card, wallet, instapay, cheque

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cash: return "نقدي"
        case .bank: return "تحويل بنكي"
        case .card: return "بطاقة"
        case .wallet: return "محفظة إلكترونية"
        case .instapay: return "InstaPay"
        case .cheque: return "شيك"
        }
    }

    var icon: String {
        switch self {
        case .cash: return "banknote"
        case .bank: return "building.columns"
        case .card: return "creditcard"
        case .wallet: return "iphone"
        case .instapay: return "bolt.fill"
        case .cheque: return "doc.plaintext"
        }
    }
}

// MARK: - Tasks

enum TaskPriority: String, CaseIterable, Identifiable, Codable {
    case low, medium, high

    var id: String { rawValue }

    var title: String {
        switch self {
        case .low: return "منخفضة"
        case .medium: return "متوسطة"
        case .high: return "عالية"
        }
    }

    var color: Color {
        switch self {
        case .low: return .gray
        case .medium: return .orange
        case .high: return .red
        }
    }

    var rank: Int {
        switch self {
        case .low: return 0
        case .medium: return 1
        case .high: return 2
        }
    }
}

// MARK: - Interactions

enum InteractionType: String, CaseIterable, Identifiable, Codable {
    case call, whatsapp, meeting, email, visit, note

    var id: String { rawValue }

    var title: String {
        switch self {
        case .call: return "مكالمة"
        case .whatsapp: return "واتساب"
        case .meeting: return "اجتماع"
        case .email: return "بريد"
        case .visit: return "زيارة"
        case .note: return "ملاحظة"
        }
    }

    var icon: String {
        switch self {
        case .call: return "phone.fill"
        case .whatsapp: return "message.fill"
        case .meeting: return "person.2.fill"
        case .email: return "envelope.fill"
        case .visit: return "car.fill"
        case .note: return "note.text"
        }
    }

    var color: Color {
        switch self {
        case .call: return .blue
        case .whatsapp: return .green
        case .meeting: return .purple
        case .email: return .orange
        case .visit: return .teal
        case .note: return .gray
        }
    }
}

// MARK: - Expenses

enum ExpenseCategory: String, CaseIterable, Identifiable, Codable {
    case rent, salaries, marketing, supplies, transport, utilities, software, other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rent: return "إيجار"
        case .salaries: return "رواتب"
        case .marketing: return "تسويق وإعلانات"
        case .supplies: return "مستلزمات"
        case .transport: return "مواصلات"
        case .utilities: return "كهرباء ومياه وإنترنت"
        case .software: return "برامج واشتراكات"
        case .other: return "أخرى"
        }
    }

    var icon: String {
        switch self {
        case .rent: return "house.fill"
        case .salaries: return "person.3.fill"
        case .marketing: return "megaphone.fill"
        case .supplies: return "shippingbox.fill"
        case .transport: return "car.fill"
        case .utilities: return "bolt.fill"
        case .software: return "app.badge.fill"
        case .other: return "ellipsis.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .rent: return .brown
        case .salaries: return .blue
        case .marketing: return .pink
        case .supplies: return .orange
        case .transport: return .teal
        case .utilities: return .yellow
        case .software: return .indigo
        case .other: return .gray
        }
    }
}

/// Common places customers come from; the field itself stays free text.
enum CustomerSources {
    static let suggestions = ["فيسبوك", "إنستجرام", "تيك توك", "واتساب", "ترشيح من عميل", "الموقع", "زيارة مباشرة", "إعلان ممول"]
}
