import Foundation

/// Central formatting so money, numbers and dates look the same everywhere.
enum Fmt {
    static var currencyCode: String {
        UserDefaults.standard.string(forKey: SettingsKey.currency) ?? "EGP"
    }

    static func makeLocale(arabicDigits: Bool) -> Locale {
        Locale(identifier: arabicDigits ? "ar_EG" : "ar_EG@numbers=latn")
    }

    static var locale: Locale {
        makeLocale(arabicDigits: UserDefaults.standard.bool(forKey: SettingsKey.arabicDigits))
    }

    static func money(_ value: Double) -> String {
        value.formatted(.currency(code: currencyCode).locale(locale).precision(.fractionLength(0...2)))
    }

    /// Short form for cards: 12.5K, 1.2M …
    static func compactMoney(_ value: Double) -> String {
        let number = value.formatted(.number.notation(.compactName).precision(.fractionLength(0...1)).locale(locale))
        return "\(number) \(currencySymbol)"
    }

    static var currencySymbol: String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = locale
        f.currencyCode = currencyCode
        return f.currencySymbol ?? currencyCode
    }

    static func number(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(locale))
    }

    static func number(_ value: Int) -> String {
        value.formatted(.number.locale(locale))
    }

    static func percent(_ value: Double) -> String {
        (value / 100).formatted(.percent.precision(.fractionLength(0...1)).locale(locale))
    }

    static func date(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale))
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(.dateTime.day().month(.abbreviated).hour().minute().locale(locale))
    }

    static func month(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year().locale(locale))
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named).locale(locale))
    }
}

/// Parses numbers typed with Arabic-Indic digits or Arabic decimal separators.
enum NumberParser {
    static func parse(_ text: String) -> Double {
        var result = ""
        for ch in text {
            if let digit = ch.wholeNumberValue, ch.isNumber {
                result += String(digit)
            } else if ch == "." || ch == "٫" || ch == "," {
                result += "."
            } else if ch == "-" && result.isEmpty {
                result += "-"
            }
        }
        return Double(result) ?? 0
    }

    static func display(_ value: Double) -> String {
        if value == 0 { return "" }
        if value == value.rounded() && abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? date
    }
}
