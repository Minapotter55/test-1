import SwiftUI
import SwiftData

@main
struct ClientProApp: App {
    init() {
        SettingsKey.registerDefaults()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [
            Customer.self,
            Deal.self,
            Invoice.self,
            InvoiceItem.self,
            Payment.self,
            Product.self,
            TaskItem.self,
            Interaction.self,
            Expense.self
        ])
    }
}

struct RootView: View {
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var isUnlocked = false

    var body: some View {
        ZStack {
            MainTabView()
            if appLock && !isUnlocked {
                LockView { isUnlocked = true }
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .appEnvironment()
        .preferredColorScheme(AppAppearance(rawValue: appearance)?.colorScheme)
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { isUnlocked = false }
        }
        .sheet(isPresented: Binding(get: { !onboarded && !(appLock && !isUnlocked) },
                                    set: { if !$0 { onboarded = true } })) {
            WelcomeView()
                .appEnvironment()
                .interactiveDismissDisabled()
        }
    }
}

struct MainTabView: View {
    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("الرئيسية", systemImage: "square.grid.2x2.fill") }
            CustomersListView()
                .tabItem { Label("العملاء", systemImage: "person.2.fill") }
            InvoicesListView()
                .tabItem { Label("الفواتير", systemImage: "doc.text.fill") }
            TasksView()
                .tabItem { Label("المهام", systemImage: "checklist") }
            MoreView()
                .tabItem { Label("المزيد", systemImage: "ellipsis.circle.fill") }
        }
    }
}

struct LockView: View {
    var onUnlock: () -> Void
    @AppStorage(SettingsKey.businessName) private var businessName = ""

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "lock.shield.fill")
                .font(.system(size: 70))
                .foregroundStyle(.tint)
            Text(businessName.isEmpty ? "ClientPro" : businessName)
                .font(.title.bold())
            Text("التطبيق مقفل لحماية بيانات عملائك")
                .foregroundStyle(.secondary)
            Button {
                unlock()
            } label: {
                Label("فتح باستخدام \(BiometricAuth.biometryName)", systemImage: BiometricAuth.biometryIcon)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
        .onAppear(perform: unlock)
    }

    private func unlock() {
        BiometricAuth.authenticate { success in
            if success { onUnlock() }
        }
    }
}

struct WelcomeView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @AppStorage(SettingsKey.onboarded) private var onboarded = false
    @AppStorage(SettingsKey.businessName) private var businessName = ""
    @AppStorage(SettingsKey.currency) private var currency = "EGP"

    private struct Feature: Identifiable {
        let icon: String
        let title: String
        let detail: String
        var id: String { title }
    }

    private let features: [Feature] = [
        Feature(icon: "person.2.fill", title: "إدارة العملاء", detail: "ملف كامل لكل عميل: تواصل، ملاحظات، وسوم، حقول مخصصة"),
        Feature(icon: "doc.text.fill", title: "فواتير ومدفوعات", detail: "فواتير PDF احترافية ومتابعة المستحقات والتحصيل"),
        Feature(icon: "chart.bar.fill", title: "داشبورد وتقارير", detail: "إيرادات، مصروفات، أرباح وأفضل العملاء لحظياً"),
        Feature(icon: "checklist", title: "مهام وتذكيرات", detail: "لا تنسَ متابعة أي عميل مع تنبيهات على الموبايل"),
        Feature(icon: "lock.shield.fill", title: "حماية وخصوصية", detail: "بياناتك على جهازك مع قفل Face ID")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.crop.rectangle.stack.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.tint)
                        .padding(.top, 20)
                    Text("أهلاً بك في ClientPro")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)
                    Text("كل ما تحتاجه لإدارة عملائك ومبيعاتك في مكان واحد")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 14) {
                                Image(systemName: feature.icon)
                                    .font(.title2)
                                    .foregroundStyle(.tint)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(feature.title).font(.headline)
                                    Text(feature.detail).font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 16))

                    VStack(alignment: .leading, spacing: 8) {
                        Text("اسم نشاطك التجاري").font(.headline)
                        TextField("مثال: مؤسسة النجاح", text: $businessName)
                            .textFieldStyle(.roundedBorder)
                        Picker("العملة", selection: $currency) {
                            ForEach(CurrencyOption.all) { option in
                                Text("\(option.name) (\(option.code))").tag(option.code)
                            }
                        }
                        .pickerStyle(.menu)
                    }

                    VStack(spacing: 12) {
                        Button {
                            finish()
                        } label: {
                            Text("ابدأ الآن").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        Button {
                            SampleData.load(into: context)
                            finish()
                        } label: {
                            Text("ابدأ ببيانات تجريبية للتعرف على التطبيق").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                    }
                }
                .padding()
            }
        }
    }

    private func finish() {
        onboarded = true
        dismiss()
    }
}
