import SwiftUI
import SwiftData
import PhotosUI

struct MoreView: View {
    @AppStorage(SettingsKey.businessName) private var businessName = ""
    @AppStorage(SettingsKey.businessLogo) private var logoData: Data?
    @Query private var deals: [Deal]
    @Query private var products: [Product]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        HStack(spacing: 14) {
                            AvatarView(name: businessName.isEmpty ? "نشاطي" : businessName, photoData: logoData, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(businessName.isEmpty ? "اسم نشاطك التجاري" : businessName).font(.headline)
                                Text("بيانات النشاط والإعدادات").font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                Section("المبيعات") {
                    link("الصفقات والفرص", "handshake.fill", .purple, badge: deals.filter { $0.stage.isOpen }.count) { DealsView() }
                    link("المنتجات والخدمات", "shippingbox.fill", .blue, badge: products.filter(\.isLowStock).count) { ProductsView() }
                }

                Section("المالية") {
                    link("المصروفات", "creditcard.fill", .red) { ExpensesView() }
                    link("التقارير", "chart.pie.fill", .green) { ReportsView() }
                }

                Section {
                    link("الإعدادات", "gearshape.fill", .gray) { SettingsView() }
                }
            }
            .navigationTitle("المزيد")
        }
    }

    private func link<Destination: View>(_ title: String, _ icon: String, _ color: Color, badge: Int = 0,
                                         @ViewBuilder destination: @escaping () -> Destination) -> some View {
        NavigationLink {
            destination()
        } label: {
            HStack {
                Image(systemName: icon)
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(color, in: RoundedRectangle(cornerRadius: 7))
                Text(title)
                Spacer()
                if badge > 0 {
                    Text(Fmt.number(badge))
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color(.tertiarySystemFill), in: Capsule())
                }
            }
        }
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var context

    @AppStorage(SettingsKey.businessName) private var businessName = ""
    @AppStorage(SettingsKey.businessPhone) private var businessPhone = ""
    @AppStorage(SettingsKey.businessEmail) private var businessEmail = ""
    @AppStorage(SettingsKey.businessAddress) private var businessAddress = ""
    @AppStorage(SettingsKey.businessTaxID) private var businessTaxID = ""
    @AppStorage(SettingsKey.businessLogo) private var logoData: Data?
    @AppStorage(SettingsKey.currency) private var currency = "EGP"
    @AppStorage(SettingsKey.countryCode) private var countryCode = "20"
    @AppStorage(SettingsKey.invoicePrefix) private var invoicePrefix = "INV-"
    @AppStorage(SettingsKey.nextInvoiceNumber) private var nextInvoiceNumber = 1
    @AppStorage(SettingsKey.defaultTaxRate) private var defaultTaxRate = 0.0
    @AppStorage(SettingsKey.defaultDueDays) private var defaultDueDays = 14
    @AppStorage(SettingsKey.invoiceFooter) private var invoiceFooter = "شكراً لتعاملكم معنا"
    @AppStorage(SettingsKey.monthlyTarget) private var monthlyTarget = 0.0
    @AppStorage(SettingsKey.appLock) private var appLock = false
    @AppStorage(SettingsKey.accent) private var accentIndex = 0
    @AppStorage(SettingsKey.appearance) private var appearance = AppAppearance.system.rawValue
    @AppStorage(SettingsKey.arabicDigits) private var arabicDigits = false

    @Query private var customers: [Customer]
    @Query private var invoices: [Invoice]
    @Query private var expenses: [Expense]

    @State private var logoItem: PhotosPickerItem?
    @State private var shareItem: ShareItem?
    @State private var confirmSample = false
    @State private var confirmWipe = false
    @State private var wipeText = ""

    var body: some View {
        Form {
            businessSection
            invoiceSection
            appearanceSection
            securitySection
            dataSection
            aboutSection
        }
        .navigationTitle("الإعدادات")
        .onChange(of: logoItem) { _, item in loadLogo(item) }
        .sheet(item: $shareItem) { ShareSheet(items: [$0.url]) }
        .alert("تحميل بيانات تجريبية؟", isPresented: $confirmSample) {
            Button("تحميل") { SampleData.load(into: context) }
            Button("إلغاء", role: .cancel) {}
        } message: {
            Text("ستُضاف بيانات تجريبية (عملاء، فواتير، صفقات...) بجانب بياناتك الحالية.")
        }
        .alert("حذف كل البيانات", isPresented: $confirmWipe) {
            TextField("اكتب: حذف", text: $wipeText)
            Button("حذف نهائياً", role: .destructive) {
                if wipeText.trimmingCharacters(in: .whitespaces) == "حذف" { wipeAll() }
                wipeText = ""
            }
            Button("إلغاء", role: .cancel) { wipeText = "" }
        } message: {
            Text("سيتم حذف كل العملاء والفواتير والصفقات والمهام والمصروفات والمنتجات. لا يمكن التراجع. اكتب كلمة «حذف» للتأكيد.")
        }
    }

    // MARK: Sections

    private var businessSection: some View {
        Section {
            HStack(spacing: 16) {
                PhotosPicker(selection: $logoItem, matching: .images) {
                    ZStack(alignment: .bottomTrailing) {
                        AvatarView(name: businessName.isEmpty ? "شعار" : businessName, photoData: logoData, size: 70)
                        Image(systemName: "camera.circle.fill").font(.title3)
                    }
                }
                .buttonStyle(.plain)
                VStack(alignment: .leading) {
                    Text("الشعار").font(.headline)
                    Text("يظهر في الفواتير PDF").font(.caption).foregroundStyle(.secondary)
                    if logoData != nil {
                        Button("إزالة الشعار", role: .destructive) { logoData = nil }
                            .font(.caption)
                            .buttonStyle(.borderless)
                    }
                }
            }
            TextField("اسم النشاط التجاري", text: $businessName)
            TextField("رقم الهاتف", text: $businessPhone).keyboardType(.phonePad)
            TextField("البريد الإلكتروني", text: $businessEmail)
                .keyboardType(.emailAddress)
                .textInputAutocapitalization(.never)
            TextField("العنوان", text: $businessAddress, axis: .vertical)
            TextField("الرقم الضريبي / السجل التجاري", text: $businessTaxID)
        } header: {
            Text("بيانات النشاط")
        }
    }

    private var invoiceSection: some View {
        Section {
            Picker("العملة", selection: $currency) {
                ForEach(CurrencyOption.all) { option in
                    Text("\(option.name) (\(option.code))").tag(option.code)
                }
            }
            LabeledContent("كود الدولة لواتساب") {
                TextField("20", text: $countryCode)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }
            LabeledContent("بادئة رقم الفاتورة") {
                TextField("INV-", text: $invoicePrefix)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 120)
            }
            Stepper("رقم الفاتورة التالية: \(Fmt.number(nextInvoiceNumber))", value: $nextInvoiceNumber, in: 1...999_999)
            LabeledContent("الضريبة الافتراضية ٪") {
                AmountField("0", value: $defaultTaxRate)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 80)
            }
            Stepper("مدة الاستحقاق: \(Fmt.number(defaultDueDays)) يوم", value: $defaultDueDays, in: 0...365)
            TextField("تذييل الفاتورة", text: $invoiceFooter, axis: .vertical)
            LabeledContent("هدف الإيرادات الشهري") {
                AmountField("0", value: $monthlyTarget)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 140)
            }
        } header: {
            Text("الفواتير والعملة")
        } footer: {
            Text("كود الدولة يُستخدم لتحويل الأرقام المحلية (مثل 010...) إلى صيغة واتساب الدولية. مصر 20، السعودية 966، الإمارات 971.")
        }
    }

    private var appearanceSection: some View {
        Section("المظهر") {
            Picker("الوضع", selection: $appearance) {
                ForEach(AppAppearance.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .pickerStyle(.segmented)
            VStack(alignment: .leading, spacing: 10) {
                Text("اللون الأساسي")
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 9), spacing: 8) {
                    ForEach(AppTheme.accents) { option in
                        Circle()
                            .fill(option.color)
                            .frame(width: 28, height: 28)
                            .overlay {
                                if option.id == accentIndex {
                                    Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                                }
                            }
                            .onTapGesture { accentIndex = option.id }
                            .accessibilityLabel(option.name)
                    }
                }
            }
            .padding(.vertical, 4)
            Toggle("أرقام عربية (١٢٣)", isOn: $arabicDigits)
        }
    }

    private var securitySection: some View {
        Section {
            Toggle(isOn: Binding(get: { appLock }, set: { newValue in
                if newValue {
                    BiometricAuth.authenticate { ok in if ok { appLock = true } }
                } else {
                    appLock = false
                }
            })) {
                Label("قفل التطبيق بـ \(BiometricAuth.biometryName)", systemImage: BiometricAuth.biometryIcon)
            }
            Button {
                NotificationManager.requestAuthorization()
            } label: {
                Label("تفعيل إشعارات التذكير", systemImage: "bell.badge")
            }
        } header: {
            Text("الحماية والتنبيهات")
        } footer: {
            Text("كل البيانات محفوظة على جهازك فقط.")
        }
    }

    private var dataSection: some View {
        Section("البيانات") {
            Button {
                if let url = CSVExporter.customers(customers) { shareItem = ShareItem(url: url) }
            } label: {
                Label("تصدير العملاء (Excel)", systemImage: "person.2")
            }
            Button {
                if let url = CSVExporter.invoices(invoices) { shareItem = ShareItem(url: url) }
            } label: {
                Label("تصدير الفواتير (Excel)", systemImage: "doc.text")
            }
            Button {
                if let url = CSVExporter.expenses(expenses) { shareItem = ShareItem(url: url) }
            } label: {
                Label("تصدير المصروفات (Excel)", systemImage: "creditcard")
            }
            Button {
                confirmSample = true
            } label: {
                Label("تحميل بيانات تجريبية", systemImage: "wand.and.stars")
            }
            Button(role: .destructive) {
                confirmWipe = true
            } label: {
                Label("حذف كل البيانات", systemImage: "trash")
            }
        }
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return version ?? "1.0"
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("الإصدار", value: appVersion)
            LabeledContent("عدد العملاء", value: Fmt.number(customers.count))
            LabeledContent("عدد الفواتير", value: Fmt.number(invoices.count))
        } header: {
            Text("عن التطبيق")
        }
    }

    // MARK: Actions

    private func loadLogo(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                let ratio = image.size.height / max(image.size.width, 1)
                let resized = image.preparingThumbnail(of: CGSize(width: 300, height: 300 * ratio)) ?? image
                logoData = resized.pngData()
            }
        }
    }

    private func deleteAll<T: PersistentModel>(_ type: T.Type) {
        let all = (try? context.fetch(FetchDescriptor<T>())) ?? []
        for object in all { context.delete(object) }
    }

    private func wipeAll() {
        NotificationManager.removeAll()
        deleteAll(Payment.self)
        deleteAll(InvoiceItem.self)
        deleteAll(Invoice.self)
        deleteAll(Deal.self)
        deleteAll(Interaction.self)
        deleteAll(TaskItem.self)
        deleteAll(Customer.self)
        deleteAll(Product.self)
        deleteAll(Expense.self)
        try? context.save()
    }
}
