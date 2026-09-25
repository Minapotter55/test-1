import Foundation
import SwiftData

/// Demo data so a new user (or a client you demo the app to) sees a full dashboard immediately.
enum SampleData {
    @MainActor
    static func load(into context: ModelContext) {
        let cal = Calendar.current
        let now = Date()
        func daysAgo(_ d: Int) -> Date { cal.date(byAdding: .day, value: -d, to: now) ?? now }
        func daysAhead(_ d: Int) -> Date { cal.date(byAdding: .day, value: d, to: now) ?? now }

        // Products & services
        let productSeeds: [(String, Double, Double, Bool, Int, String)] = [
            ("استشارة", 500, 0, true, 0, "خدمات"),
            ("باقة شهرية", 3000, 800, true, 0, "خدمات"),
            ("تصميم هوية بصرية", 7500, 1500, true, 0, "تصميم"),
            ("منتج أساسي", 250, 120, false, 40, "منتجات"),
            ("منتج مميز", 900, 450, false, 3, "منتجات")
        ]
        var products: [Product] = []
        for seed in productSeeds {
            let p = Product(name: seed.0, price: seed.1, isService: seed.3)
            p.cost = seed.2
            p.trackStock = !seed.3
            p.stock = seed.4
            p.category = seed.5
            context.insert(p)
            products.append(p)
        }

        // Customers
        let customerSeeds: [(String, String, String, CustomerStatus, String, String)] = [
            ("أحمد محمود", "01001234567", "شركة النور للتجارة", .vip, "القاهرة", "ترشيح من عميل"),
            ("سارة علي", "01112345678", "", .active, "الجيزة", "إنستجرام"),
            ("محمد حسن", "01223456789", "مطعم الشرق", .active, "الإسكندرية", "فيسبوك"),
            ("منى إبراهيم", "01534567890", "عيادة د. منى", .prospect, "المنصورة", "إعلان ممول"),
            ("خالد يوسف", "01045678901", "معرض يوسف للسيارات", .lead, "القاهرة", "الموقع"),
            ("ياسمين طارق", "01156789012", "", .active, "طنطا", "تيك توك"),
            ("عمر سمير", "01267890123", "صيدلية الشفاء", .inactive, "أسيوط", "زيارة مباشرة"),
            ("نورا عادل", "01078901234", "أكاديمية نورا", .vip, "القاهرة", "ترشيح من عميل")
        ]
        var customers: [Customer] = []
        let ratings = [5, 4, 4, 3, 2, 4, 2, 5]
        for (i, seed) in customerSeeds.enumerated() {
            let c = Customer(name: seed.0, phone: seed.1, company: seed.2, status: seed.3)
            c.city = seed.4
            c.source = seed.5
            c.rating = ratings[i % ratings.count]
            c.isFavorite = seed.3 == .vip
            c.tags = i % 2 == 0 ? ["جملة"] : ["تجزئة"]
            c.createdAt = daysAgo(170 - i * 18)
            c.lastContactAt = daysAgo(i * 3 + 1)
            c.email = "client\(i + 1)@example.com"
            context.insert(c)
            customers.append(c)
        }

        // Invoices with items and payments spread over the last 6 months
        var invoiceNo = 1
        let methods: [PaymentMethod] = [.cash, .instapay, .bank]
        for monthBack in 0..<6 {
            for j in 0..<3 {
                let customer = customers[(monthBack * 3 + j) % customers.count]
                let issue = cal.date(byAdding: .day, value: -(monthBack * 30 + j * 7 + 2), to: now) ?? now
                let invoice = Invoice(number: "INV-" + String(format: "%04ld", invoiceNo),
                                      issueDate: issue,
                                      dueDate: cal.date(byAdding: .day, value: 14, to: issue) ?? issue)
                invoiceNo += 1
                context.insert(invoice)
                invoice.customer = customer

                let picks = [products[(monthBack + j) % products.count], products[(monthBack + j + 2) % products.count]]
                for (k, product) in picks.enumerated() {
                    let item = InvoiceItem(name: product.name, quantity: Double(k + 1), unitPrice: product.price, sortIndex: k)
                    context.insert(item)
                    item.invoice = invoice
                }
                let total = picks.enumerated().reduce(0.0) { $0 + Double($1.offset + 1) * $1.element.price }

                // Older invoices are paid, recent ones partially / unpaid.
                let paid: Double
                if monthBack >= 2 { paid = total } else if j == 0 { paid = total / 2 } else if j == 1 { paid = 0 } else { paid = total }
                if paid > 0 {
                    let payment = Payment(amount: paid, date: cal.date(byAdding: .day, value: 3, to: issue) ?? issue,
                                          method: methods[j % methods.count])
                    context.insert(payment)
                    payment.invoice = invoice
                }
            }
        }
        UserDefaults.standard.set(max(invoiceNo, UserDefaults.standard.integer(forKey: SettingsKey.nextInvoiceNumber)),
                                  forKey: SettingsKey.nextInvoiceNumber)

        // Deals
        let dealSeeds: [(String, Double, DealStage, Int)] = [
            ("تجديد العقد السنوي", 36000, .negotiation, 0),
            ("حملة إعلانية رمضان", 15000, .proposal, 2),
            ("تصميم منيو جديد", 7500, .contacted, 2),
            ("باقة سوشيال ميديا", 9000, .new, 3),
            ("موقع إلكتروني", 25000, .proposal, 4),
            ("توريد منتجات", 12000, .won, 5),
            ("إدارة صفحات", 6000, .lost, 6),
            ("برنامج ولاء العملاء", 18000, .won, 7)
        ]
        for seed in dealSeeds {
            let d = Deal(title: seed.0, value: seed.1, stage: seed.2)
            d.expectedCloseDate = daysAhead(Int.random(in: 5...40))
            d.createdAt = daysAgo(Int.random(in: 5...60))
            if !seed.2.isOpen { d.closedAt = daysAgo(Int.random(in: 1...20)) }
            context.insert(d)
            d.customer = customers[seed.3]
        }

        // Tasks
        let taskSeeds: [(String, Int, TaskPriority, Int?)] = [
            ("متابعة عرض السعر", 0, .high, 1),
            ("إرسال الفاتورة المتأخرة", -2, .high, 0),
            ("مكالمة ترحيب بالعميل الجديد", 1, .medium, 4),
            ("تحضير عرض تقديمي", 3, .medium, 3),
            ("طلب تقييم من العميل", 5, .low, 5),
            ("مراجعة المصروفات الشهرية", 7, .low, nil)
        ]
        for seed in taskSeeds {
            let due = cal.date(bySettingHour: 11, minute: 0, second: 0, of: daysAhead(seed.1)) ?? daysAhead(seed.1)
            let t = TaskItem(title: seed.0, dueDate: due, priority: seed.2)
            context.insert(t)
            if let idx = seed.3 { t.customer = customers[idx] }
        }

        // Interactions
        let interactionSeeds: [(InteractionType, String, Int, Int)] = [
            (.call, "اتصل يسأل عن الأسعار الجديدة", 0, 1),
            (.whatsapp, "أرسلت له عرض السعر على واتساب", 1, 2),
            (.meeting, "اجتماع لمناقشة الخطة الشهرية", 0, 6),
            (.visit, "زيارة للمقر وتسليم الطلبية", 2, 9),
            (.note, "يفضل التواصل بعد الساعة 5 مساءً", 3, 12)
        ]
        for seed in interactionSeeds {
            let it = Interaction(type: seed.0, summary: seed.1, date: daysAgo(seed.3))
            context.insert(it)
            it.customer = customers[seed.2]
        }

        // Expenses
        for monthBack in 0..<6 {
            let base = cal.date(byAdding: .month, value: -monthBack, to: now) ?? now
            let start = cal.startOfMonth(for: base)
            let expenseSeeds: [(String, Double, ExpenseCategory, Int)] = [
                ("إيجار المكتب", 4000, .rent, 1),
                ("رواتب", 9000, .salaries, 25),
                ("إعلانات فيسبوك", Double(1500 + monthBack * 200), .marketing, 10),
                ("إنترنت وكهرباء", 650, .utilities, 5)
            ]
            for seed in expenseSeeds {
                let date = cal.date(byAdding: .day, value: seed.3 - 1, to: start) ?? start
                if date > now { continue }
                context.insert(Expense(title: seed.0, amount: seed.1, category: seed.2, date: date))
            }
        }

        try? context.save()
    }
}
