import SwiftUI
import SwiftData
import PhotosUI
import Contacts

struct CustomerFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let customer: Customer?

    @State private var name: String
    @State private var company: String
    @State private var phone: String
    @State private var whatsapp: String
    @State private var email: String
    @State private var city: String
    @State private var address: String
    @State private var source: String
    @State private var notes: String
    @State private var status: CustomerStatus
    @State private var rating: Int
    @State private var tags: [String]
    @State private var hasBirthday: Bool
    @State private var birthday: Date
    @State private var photoData: Data?
    @State private var customFields: [CustomField]

    @State private var photoItem: PhotosPickerItem?
    @State private var showContacts = false

    init(customer: Customer? = nil) {
        self.customer = customer
        _name = State(initialValue: customer?.name ?? "")
        _company = State(initialValue: customer?.company ?? "")
        _phone = State(initialValue: customer?.phone ?? "")
        _whatsapp = State(initialValue: customer?.whatsapp ?? "")
        _email = State(initialValue: customer?.email ?? "")
        _city = State(initialValue: customer?.city ?? "")
        _address = State(initialValue: customer?.address ?? "")
        _source = State(initialValue: customer?.source ?? "")
        _notes = State(initialValue: customer?.notes ?? "")
        _status = State(initialValue: customer?.status ?? .lead)
        _rating = State(initialValue: customer?.rating ?? 0)
        _tags = State(initialValue: customer?.tags ?? [])
        _hasBirthday = State(initialValue: customer?.birthday != nil)
        _birthday = State(initialValue: customer?.birthday ?? Date())
        _photoData = State(initialValue: customer?.photoData)
        _customFields = State(initialValue: customer?.customFields ?? [])
    }

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            ZStack(alignment: .bottomTrailing) {
                                AvatarView(name: name, photoData: photoData, size: 72, color: status.color)
                                Image(systemName: "camera.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(.white, Color.accentColor)
                            }
                        }
                        .buttonStyle(.plain)
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("اسم العميل *", text: $name)
                                .font(.headline)
                                .textContentType(.name)
                            TextField("الشركة / النشاط", text: $company)
                                .textContentType(.organizationName)
                        }
                    }
                    if customer == nil {
                        Button {
                            showContacts = true
                        } label: {
                            Label("استيراد من جهات الاتصال", systemImage: "person.crop.circle.badge.plus")
                        }
                    }
                    if photoData != nil {
                        Button("إزالة الصورة", role: .destructive) { photoData = nil }
                    }
                }

                Section("التواصل") {
                    TextField("رقم الهاتف", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("رقم واتساب (إذا كان مختلفاً)", text: $whatsapp)
                        .keyboardType(.phonePad)
                    TextField("البريد الإلكتروني", text: $email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("المدينة", text: $city)
                    TextField("العنوان", text: $address, axis: .vertical)
                }

                Section("التصنيف") {
                    Picker("الحالة", selection: $status) {
                        ForEach(CustomerStatus.allCases) { s in
                            Label(s.title, systemImage: s.icon).tag(s)
                        }
                    }
                    HStack {
                        Text("التقييم")
                        Spacer()
                        RatingView(rating: $rating)
                    }
                    HStack {
                        TextField("مصدر العميل", text: $source)
                        Menu {
                            ForEach(CustomerSources.suggestions, id: \.self) { s in
                                Button(s) { source = s }
                            }
                        } label: {
                            Image(systemName: "chevron.down.circle")
                        }
                    }
                    TagsEditor(tags: $tags)
                }

                Section("تاريخ الميلاد") {
                    Toggle("إضافة تاريخ الميلاد", isOn: $hasBirthday)
                    if hasBirthday {
                        DatePicker("التاريخ", selection: $birthday, displayedComponents: .date)
                    }
                }

                Section {
                    ForEach($customFields) { $field in
                        HStack {
                            TextField("اسم الحقل", text: $field.key)
                                .frame(maxWidth: 120)
                            Divider()
                            TextField("القيمة", text: $field.value)
                        }
                    }
                    .onDelete { customFields.remove(atOffsets: $0) }
                    Button {
                        customFields.append(CustomField(key: "", value: ""))
                    } label: {
                        Label("إضافة حقل مخصص", systemImage: "plus")
                    }
                } header: {
                    Text("حقول مخصصة")
                } footer: {
                    Text("أضف أي معلومة تحتاجها لنشاطك: رقم السجل، المقاس، رقم العقد، ...")
                }

                Section("ملاحظات") {
                    TextField("اكتب أي ملاحظات عن العميل", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }
            }
            .navigationTitle(customer == nil ? "عميل جديد" : "تعديل العميل")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("إلغاء") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("حفظ") { save() }
                        .bold()
                        .disabled(!canSave)
                }
            }
            .background(ContactPickerPresenter(isPresented: $showContacts, onSelect: fill(from:)))
            .onChange(of: photoItem) { _, item in
                loadPhoto(item)
            }
        }
    }

    private func fill(from contact: CNContact) {
        let fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
        if !fullName.isEmpty { name = fullName }
        if !contact.organizationName.isEmpty { company = contact.organizationName }
        if let number = contact.phoneNumbers.first?.value.stringValue { phone = number }
        if let mail = contact.emailAddresses.first?.value { email = mail as String }
        if let postal = contact.postalAddresses.first?.value {
            city = postal.city
            address = postal.street
        }
        if let data = contact.thumbnailImageData { photoData = data }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                let resized = image.preparingThumbnail(of: CGSize(width: 400, height: 400 * image.size.height / max(image.size.width, 1)))
                photoData = (resized ?? image).jpegData(compressionQuality: 0.8)
            }
        }
    }

    private func save() {
        let target: Customer
        if let customer {
            target = customer
        } else {
            target = Customer(name: name)
            context.insert(target)
        }
        target.name = name.trimmingCharacters(in: .whitespaces)
        target.company = company
        target.phone = phone
        target.whatsapp = whatsapp
        target.email = email.trimmingCharacters(in: .whitespaces)
        target.city = city
        target.address = address
        target.source = source
        target.notes = notes
        target.status = status
        target.rating = rating
        target.tags = tags
        target.birthday = hasBirthday ? birthday : nil
        target.photoData = photoData
        target.customFields = customFields.filter { !$0.key.trimmingCharacters(in: .whitespaces).isEmpty }
        try? context.save()
        dismiss()
    }
}

struct InteractionFormView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    let customer: Customer
    @State private var type: InteractionType = .call
    @State private var summary = ""
    @State private var date = Date()
    @State private var addFollowUp = false
    @State private var followUpDate = Calendar.current.date(byAdding: .day, value: 3, to: Date()) ?? Date()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("نوع التواصل", selection: $type) {
                        ForEach(InteractionType.allCases) { t in
                            Label(t.title, systemImage: t.icon).tag(t)
                        }
                    }
                    .pickerStyle(.menu)
                    DatePicker("التاريخ", selection: $date)
                }
                Section("ماذا حدث؟") {
                    TextField("مثال: اتفقنا على إرسال عرض سعر يوم الأحد", text: $summary, axis: .vertical)
                        .lineLimit(3...8)
                }
                Section {
                    Toggle("إنشاء مهمة متابعة", isOn: $addFollowUp)
                    if addFollowUp {
                        DatePicker("موعد المتابعة", selection: $followUpDate)
                    }
                }
            }
            .navigationTitle("تسجيل تواصل مع \(customer.name)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("حفظ") { save() }.bold() }
            }
        }
    }

    private func save() {
        let item = Interaction(type: type, summary: summary, date: date)
        context.insert(item)
        item.customer = customer
        if (customer.lastContactAt ?? .distantPast) < date { customer.lastContactAt = date }

        if addFollowUp {
            let task = TaskItem(title: "متابعة مع \(customer.name)", dueDate: followUpDate, priority: .medium)
            task.notes = summary
            task.reminderEnabled = true
            context.insert(task)
            task.customer = customer
            NotificationManager.requestAuthorization()
            NotificationManager.schedule(for: task)
        }
        try? context.save()
        dismiss()
    }
}
