import SwiftUI

/// UserDefaults keys. Every `@AppStorage` in the app uses one of these.
enum SettingsKey {
    static let businessName = "businessName"
    static let businessPhone = "businessPhone"
    static let businessEmail = "businessEmail"
    static let businessAddress = "businessAddress"
    static let businessTaxID = "businessTaxID"
    static let businessLogo = "businessLogo"
    static let currency = "currencyCode"
    static let countryCode = "countryCode"
    static let invoicePrefix = "invoicePrefix"
    static let nextInvoiceNumber = "nextInvoiceNumber"
    static let defaultTaxRate = "defaultTaxRate"
    static let defaultDueDays = "defaultDueDays"
    static let invoiceFooter = "invoiceFooter"
    static let appLock = "appLockEnabled"
    static let accent = "accentIndex"
    static let appearance = "appearance"
    static let arabicDigits = "arabicDigits"
    static let onboarded = "didOnboard"
    static let monthlyTarget = "monthlyTarget"

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            currency: "EGP",
            countryCode: "20",
            invoicePrefix: "INV-",
            nextInvoiceNumber: 1,
            defaultTaxRate: 0.0,
            defaultDueDays: 14,
            invoiceFooter: "شكراً لتعاملكم معنا",
            accent: 0,
            appearance: AppAppearance.system.rawValue,
            arabicDigits: false,
            monthlyTarget: 0.0
        ])
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "تلقائي"
        case .light: return "فاتح"
        case .dark: return "داكن"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

struct AccentOption: Identifiable {
    let id: Int
    let name: String
    let color: Color
}

enum AppTheme {
    static let accents: [AccentOption] = [
        AccentOption(id: 0, name: "أزرق", color: .blue),
        AccentOption(id: 1, name: "نيلي", color: .indigo),
        AccentOption(id: 2, name: "بنفسجي", color: .purple),
        AccentOption(id: 3, name: "وردي", color: .pink),
        AccentOption(id: 4, name: "أحمر", color: .red),
        AccentOption(id: 5, name: "برتقالي", color: .orange),
        AccentOption(id: 6, name: "أخضر", color: .green),
        AccentOption(id: 7, name: "تركواز", color: .teal),
        AccentOption(id: 8, name: "بني", color: .brown)
    ]

    static func accent(_ index: Int) -> Color {
        accents.first { $0.id == index }?.color ?? .blue
    }
}

struct CurrencyOption: Identifiable {
    let code: String
    let name: String
    var id: String { code }

    static let all: [CurrencyOption] = [
        CurrencyOption(code: "EGP", name: "جنيه مصري"),
        CurrencyOption(code: "SAR", name: "ريال سعودي"),
        CurrencyOption(code: "AED", name: "درهم إماراتي"),
        CurrencyOption(code: "KWD", name: "دينار كويتي"),
        CurrencyOption(code: "QAR", name: "ريال قطري"),
        CurrencyOption(code: "BHD", name: "دينار بحريني"),
        CurrencyOption(code: "OMR", name: "ريال عماني"),
        CurrencyOption(code: "JOD", name: "دينار أردني"),
        CurrencyOption(code: "LYD", name: "دينار ليبي"),
        CurrencyOption(code: "MAD", name: "درهم مغربي"),
        CurrencyOption(code: "IQD", name: "دينار عراقي"),
        CurrencyOption(code: "USD", name: "دولار أمريكي"),
        CurrencyOption(code: "EUR", name: "يورو"),
        CurrencyOption(code: "GBP", name: "جنيه إسترليني")
    ]
}

/// Invoice numbering: prefix + zero padded running number.
enum InvoiceNumbering {
    static func peekNext() -> String {
        let d = UserDefaults.standard
        let prefix = d.string(forKey: SettingsKey.invoicePrefix) ?? "INV-"
        let n = max(1, d.integer(forKey: SettingsKey.nextInvoiceNumber))
        return prefix + String(format: "%04ld", n)
    }

    static func advance() {
        let d = UserDefaults.standard
        let n = max(1, d.integer(forKey: SettingsKey.nextInvoiceNumber))
        d.set(n + 1, forKey: SettingsKey.nextInvoiceNumber)
    }
}

/// Applies RTL, locale and accent colour. Used on the root and on every sheet
/// so presented screens always match the app look.
struct AppEnvironment: ViewModifier {
    @AppStorage(SettingsKey.accent) private var accentIndex = 0
    @AppStorage(SettingsKey.arabicDigits) private var arabicDigits = false

    func body(content: Content) -> some View {
        content
            .tint(AppTheme.accent(accentIndex))
            .environment(\.layoutDirection, .rightToLeft)
            .environment(\.locale, Fmt.makeLocale(arabicDigits: arabicDigits))
    }
}

extension View {
    func appEnvironment() -> some View { modifier(AppEnvironment()) }
}
