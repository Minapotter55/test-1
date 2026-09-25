import Foundation
import LocalAuthentication
import UserNotifications

// MARK: - Calls / WhatsApp / Email / Maps

enum ContactActions {
    private static func digits(_ raw: String) -> String {
        raw.compactMap { $0.isNumber ? $0.wholeNumberValue : nil }.map(String.init).joined()
    }

    /// International number without "+" as WhatsApp expects (e.g. 2010xxxxxxx).
    static func internationalDigits(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        let d = digits(trimmed)
        if trimmed.hasPrefix("+") { return d }
        if d.hasPrefix("00") { return String(d.dropFirst(2)) }
        if d.hasPrefix("0") {
            let code = UserDefaults.standard.string(forKey: SettingsKey.countryCode) ?? "20"
            return code + String(d.dropFirst())
        }
        return d
    }

    static func callURL(_ phone: String) -> URL? {
        let d = digits(phone)
        guard !d.isEmpty else { return nil }
        let prefix = phone.trimmingCharacters(in: .whitespaces).hasPrefix("+") ? "+" : ""
        return URL(string: "tel:\(prefix)\(d)")
    }

    static func smsURL(_ phone: String) -> URL? {
        let d = digits(phone)
        guard !d.isEmpty else { return nil }
        return URL(string: "sms:\(d)")
    }

    static func whatsappURL(_ phone: String, text: String = "") -> URL? {
        let d = internationalDigits(phone)
        guard !d.isEmpty else { return nil }
        var comps = URLComponents(string: "https://wa.me/\(d)")
        if !text.isEmpty { comps?.queryItems = [URLQueryItem(name: "text", value: text)] }
        return comps?.url
    }

    static func emailURL(_ email: String, subject: String = "") -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents()
        comps.scheme = "mailto"
        comps.path = trimmed
        if !subject.isEmpty { comps.queryItems = [URLQueryItem(name: "subject", value: subject)] }
        return comps.url
    }

    static func mapsURL(_ address: String) -> URL? {
        let trimmed = address.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        var comps = URLComponents(string: "http://maps.apple.com/")
        comps?.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return comps?.url
    }
}

// MARK: - Face ID / passcode

enum BiometricAuth {
    static func authenticate(completion: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        // A device without a passcode cannot be locked; never lock the owner out.
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            completion(true)
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح التطبيق للوصول إلى بيانات عملائك") { success, _ in
            DispatchQueue.main.async { completion(success) }
        }
    }

    static var biometryName: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        default: return "رمز الجهاز"
        }
    }

    static var biometryIcon: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.fill"
        }
    }
}

// MARK: - Task reminders

enum NotificationManager {
    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(for task: TaskItem) {
        cancel(id: task.notificationID)
        guard task.reminderEnabled, !task.isDone, let due = task.dueDate, due > Date() else { return }

        let content = UNMutableNotificationContent()
        content.title = "تذكير بمهمة"
        if let customer = task.customer {
            content.body = "\(task.title) — \(customer.name)"
        } else {
            content.body = task.title
        }
        content.sound = .default

        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: due)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: task.notificationID, content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    static func cancel(id: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [id])
    }

    static func removeAll() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    }
}
