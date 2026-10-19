import Foundation
import SwiftData

/// Six months of realistic Bangkok spending so charts, bills and forecasts have something to show in the demo.
enum SampleData {
    private static let seededKey = "didSeedSampleData"

    static func seedIfNeeded(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else {
            addSampleIncomeIfMissing(in: context)
            return
        }
        let existing = (try? context.fetchCount(FetchDescriptor<Receipt>())) ?? 0
        if existing == 0 { seed(in: context) }
        UserDefaults.standard.set(true, forKey: seededKey)
        UserDefaults.standard.set(true, forKey: incomeKey)
    }

    private static let incomeKey = "sampleIncomeAdded"

    /// Sample data saved before income existed gets its pay and side jobs once.
    private static func addSampleIncomeIfMissing(in context: ModelContext) {
        guard !UserDefaults.standard.bool(forKey: incomeKey) else { return }
        UserDefaults.standard.set(true, forKey: incomeKey)
        let samples = FetchDescriptor<Receipt>(predicate: #Predicate { $0.reader == "Sample" }, sortBy: [SortDescriptor(\.date)])
        let incomes = (try? context.fetchCount(FetchDescriptor<Receipt>(predicate: #Predicate { $0.isIncome == true }))) ?? 0
        guard incomes == 0, let first = try? context.fetch(samples).first else { return }
        addIncome(from: first.date.startOfMonth, to: .now, in: context)
        try? context.save()
    }

    static func reset(in context: ModelContext) {
        try? context.delete(model: LineItem.self)
        try? context.delete(model: Receipt.self)
        seed(in: context)
        UserDefaults.standard.set(true, forKey: seededKey)
    }

    static func removeAll(in context: ModelContext) {
        try? context.delete(model: LineItem.self)
        try? context.delete(model: Receipt.self)
        try? context.save()
    }

    // MARK: - Shops

    private struct Product {
        let name: String
        let price: Double
        let category: SpendCategory
    }

    private struct Shop {
        let name: String
        let products: [Product]
        let items: ClosedRange<Int>
        let hours: ClosedRange<Int>
        var fullTaxInvoiceChance = 0.0
        var maxQuantity = 1
        /// For fares and fuel: one line whose price varies.
        var priceRange: ClosedRange<Double>?
    }

    private static func p(_ name: String, _ price: Double, _ category: SpendCategory) -> Product {
        Product(name: name, price: price, category: category)
    }

    private static let sevenEleven = Shop(name: "7-Eleven", products: [
        p("ข้าวกะเพราไก่ไข่ดาว ซีพี", 49, .dining), p("แซนด์วิชแฮมชีส", 35, .dining), p("All Café ลาเต้เย็น", 40, .dining),
        p("นมจืดเมจิ 450 มล.", 25, .groceries), p("น้ำดื่มคริสตัล 600 มล.", 7, .groceries), p("โออิชิ ชาเขียว", 20, .groceries),
        p("มาม่า ต้มยำกุ้ง", 7, .groceries), p("ไส้กรอกชีส", 35, .dining), p("ยาสีฟันคอลเกต", 49, .health),
        p("ทิชชู่เปียก", 29, .home), p("ขนมปังฟาร์มเฮ้าส์", 27, .groceries), p("ซาลาเปาหมูสับ", 25, .dining),
    ], items: 1...4, hours: 7...22, maxQuantity: 2)

    private static let cafeAmazon = Shop(name: "Café Amazon", products: [
        p("อเมริกาโน่เย็น", 55, .dining), p("ลาเต้เย็น", 65, .dining), p("ชาไทยเย็น", 60, .dining),
        p("มัทฉะลาเต้", 70, .dining), p("ครัวซองต์เนยสด", 45, .dining),
    ], items: 1...2, hours: 7...10)

    private static let foodCourt = Shop(name: "ฟู้ดคอร์ท อาคารสำนักงาน", products: [
        p("ข้าวมันไก่", 60, .dining), p("ก๋วยเตี๋ยวเรือ", 70, .dining), p("ผัดไทยกุ้งสด", 85, .dining),
        p("ข้าวขาหมู", 70, .dining), p("ส้มตำไทย", 50, .dining), p("ข้าวผัดกะเพราหมู", 65, .dining), p("น้ำลำไย", 25, .dining),
    ], items: 1...2, hours: 11...13)

    private static let bts = Shop(name: "BTS Skytrain", products: [p("ค่าโดยสาร BTS", 0, .transport)],
                                  items: 1...1, hours: 8...9, priceRange: 34...62)
    private static let grab = Shop(name: "Grab", products: [p("Grab ride", 0, .transport)],
                                   items: 1...1, hours: 9...23, priceRange: 95...280)
    private static let ptt = Shop(name: "PTT Station", products: [p("แก๊สโซฮอล์ 95", 0, .transport)],
                                  items: 1...1, hours: 8...20, fullTaxInvoiceChance: 0.3, priceRange: 900...1_500)

    private static let groceries: [Shop] = [
        Shop(name: "Lotus's", products: groceryProducts, items: 6...14, hours: 10...19, fullTaxInvoiceChance: 0.3, maxQuantity: 3),
        Shop(name: "Big C Supercenter", products: groceryProducts, items: 6...16, hours: 10...19, fullTaxInvoiceChance: 0.35, maxQuantity: 3),
        Shop(name: "Tops", products: groceryProducts, items: 4...10, hours: 11...20, fullTaxInvoiceChance: 0.4, maxQuantity: 2),
        Shop(name: "Makro", products: groceryProducts, items: 8...16, hours: 9...17, fullTaxInvoiceChance: 0.6, maxQuantity: 4),
    ]

    private static let groceryProducts: [Product] = [
        p("นมจืด ไทย-เดนมาร์ก 2 ลิตร", 95, .groceries), p("ไข่ไก่ เบอร์ 2 แพ็ค 10", 59, .groceries), p("ข้าวหอมมะลิ 5 กก.", 235, .groceries),
        p("อกไก่ ซีพี 1 กก.", 129, .groceries), p("หมูสับ 500 ก.", 89, .groceries), p("ปลาแซลมอน 200 ก.", 199, .groceries),
        p("ผักกาดหอม", 35, .groceries), p("มะเขือเทศ 500 ก.", 32, .groceries), p("กล้วยหอม", 45, .groceries),
        p("ส้มสายน้ำผึ้ง 1 กก.", 79, .groceries), p("น้ำปลาทิพรส", 32, .groceries), p("น้ำมันพืชองุ่น 1 ลิตร", 58, .groceries),
        p("โยเกิร์ต ดัชชี่", 18, .groceries), p("ขนมปังโฮลวีท", 45, .groceries), p("น้ำดื่ม 6 ขวด", 42, .groceries),
        p("น้ำยาล้างจานซันไลต์", 45, .home), p("ผงซักฟอกบรีส", 159, .home), p("กระดาษทิชชู่ 6 ม้วน", 119, .home),
        p("ถุงขยะ", 39, .home), p("ยาสีฟันคอลเกต", 89, .health), p("แชมพูซันซิล", 129, .health),
    ]

    private static let diningOut: [Shop] = [
        Shop(name: "MK Restaurants", products: [
            p("ชุดผักรวม", 150, .dining), p("เป็ดย่าง", 280, .dining), p("ติ่มซำรวม", 120, .dining),
            p("หมูนุ่ม", 110, .dining), p("เกี๊ยวกุ้ง", 75, .dining), p("ข้าวผัด", 60, .dining),
        ], items: 3...6, hours: 12...20),
        Shop(name: "Bar B Q Plaza", products: [
            p("ชุดพลาซ่า", 499, .dining), p("เนื้อสไลซ์", 179, .dining), p("ชาเขียวรีฟิล", 69, .dining),
        ], items: 2...4, hours: 12...20),
        Shop(name: "Starbucks", products: [
            p("Caffè Latte Grande", 145, .dining), p("Java Chip Frappuccino", 175, .dining), p("Blueberry Cheesecake", 135, .dining),
        ], items: 1...3, hours: 9...20),
        Shop(name: "After You Dessert Café", products: [
            p("Shibuya Honey Toast", 245, .dining), p("Mango Sticky Rice Kakigori", 295, .dining), p("Iced Thai Tea", 95, .dining),
        ], items: 1...3, hours: 13...21),
    ]

    private static let shopping: [Shop] = [
        Shop(name: "Uniqlo", products: [
            p("AIRism Cotton T-Shirt", 390, .shopping), p("Ultra Stretch Jeans", 1_490, .shopping),
            p("Socks 3 Pairs", 290, .shopping), p("Pocketable Parka", 1_290, .shopping),
        ], items: 1...3, hours: 12...20, fullTaxInvoiceChance: 0.5),
        Shop(name: "Watsons", products: [
            p("ครีมกันแดด Biore", 299, .health), p("วิตามินซี Blackmores", 350, .health),
            p("โฟมล้างหน้า Senka", 159, .health), p("แชมพู Head & Shoulders", 189, .health),
        ], items: 1...3, hours: 11...20, fullTaxInvoiceChance: 0.2),
        Shop(name: "HomePro", products: [
            p("หลอดไฟ LED Philips", 129, .home), p("ปลั๊กพ่วง Toshino", 399, .home), p("กล่องเก็บของ", 259, .home),
            p("กระทะเคลือบ 28 ซม.", 790, .home), p("พัดลมตั้งพื้น Hatari", 1_290, .home),
        ], items: 1...3, hours: 11...19, fullTaxInvoiceChance: 0.8),
        Shop(name: "Central World", products: [
            p("รองเท้าผ้าใบ", 2_490, .shopping), p("เสื้อเชิ้ต", 1_290, .shopping), p("กระเป๋าเป้", 1_890, .shopping),
        ], items: 1...2, hours: 13...20, fullTaxInvoiceChance: 0.5),
    ]

    private static let cinema = Shop(name: "Major Cineplex", products: [
        p("ตั๋วหนัง", 260, .entertainment), p("ป๊อปคอร์นคอมโบ", 249, .entertainment),
    ], items: 2...2, hours: 14...21, maxQuantity: 2)

    // MARK: - Seeding

    static func seed(in context: ModelContext, now: Date = .now) {
        var rng = SeededGenerator(seed: 2569)
        let calendar = Calendar.app
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .month, value: -6, to: today.startOfMonth)!
        var day = start
        var nextFuel = calendar.date(byAdding: .day, value: 3, to: start)!

        while day <= today {
            let weekday = calendar.component(.weekday, from: day)
            let dayOfMonth = calendar.component(.day, from: day)
            let isWeekend = weekday == 1 || weekday == 7
            let afterPayday = dayOfMonth >= 25 || dayOfMonth <= 3

            func add(_ shop: Shop, _ chance: Double) {
                if Double.random(in: 0..<1, using: &rng) < chance { insert(shop, on: day, now: now, rng: &rng, in: context) }
            }

            if isWeekend {
                add(groceries.randomElement(using: &rng)!, 0.55)
                add(diningOut.randomElement(using: &rng)!, 0.7)
                add(shopping.randomElement(using: &rng)!, afterPayday ? 0.5 : 0.2)
                add(cinema, 0.2)
                add(grab, 0.35)
                add(sevenEleven, 0.6)
            } else {
                add(cafeAmazon, 0.7)
                add(bts, 0.8)
                add(foodCourt, 0.85)
                add(sevenEleven, 0.5)
                add(grab, 0.15)
                add(diningOut.randomElement(using: &rng)!, afterPayday ? 0.3 : 0.12)
            }
            if day >= nextFuel {
                insert(ptt, on: day, now: now, rng: &rng, in: context)
                nextFuel = calendar.date(byAdding: .day, value: Int.random(in: 8...11, using: &rng), to: day)!
            }

            addBills(on: day, dayOfMonth: dayOfMonth, now: now, rng: &rng, in: context)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }

        // The one-off that makes "what cost so much, and when" interesting.
        if let splurgeDay = calendar.date(byAdding: .day, value: -52, to: today) {
            let date = calendar.date(bySettingHour: 15, minute: 20, second: 0, of: splurgeDay)!
            make(shop: "Power Buy", date: date, isFullTaxInvoice: true,
                 items: [("iPad Air 11 นิ้ว", 1, 21_900, .shopping), ("Apple Pencil Pro", 1, 4_390, .shopping)], in: context)
        }
        addIncome(from: start, to: now, in: context)
        try? context.save()
    }

    /// Pay on the 25th, a freelance job now and then, and one thing sold. Kept apart from spending.
    private static func addIncome(from start: Date, to now: Date, in context: ModelContext) {
        let calendar = Calendar.app
        func income(_ name: String, _ source: IncomeSource, _ amount: Double, _ date: Date) {
            guard date <= now else { return }
            let receipt = Receipt(shopName: name, date: date, total: amount, vat: 0, kind: .purchase,
                                  isFullTaxInvoice: false, reader: "Sample")
            receipt.isIncome = true
            receipt.incomeSource = source
            context.insert(receipt)
        }
        var month = start.startOfMonth
        var index = 0
        while month <= now {
            if let payday = calendar.date(bySetting: .day, value: 25, of: month) {
                income("เงินเดือน", .salary, 45_000, at(payday, hour: 9))
            }
            if index % 2 == 1, let day = calendar.date(byAdding: .day, value: 9, to: month) {
                income("Logo design job", .freelance, 6_500, at(day, hour: 16))
            }
            index += 1
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        if let day = calendar.date(byAdding: .day, value: -9, to: now) {
            income("ขายรองเท้ามือสอง", .sales, 1_200, at(day, hour: 19))
        }
    }

    private static func addBills(on day: Date, dayOfMonth: Int, now: Date, rng: inout SeededGenerator, in context: ModelContext) {
        let month = Calendar.app.component(.month, from: day)
        if dayOfMonth == 20 {
            // Electricity peaks in the hot season (March–May) when the air conditioner runs all day.
            let base: Double = switch month {
            case 3, 4, 5: 3_150
            case 6, 7, 8, 9: 2_450
            default: 1_900
            }
            let amount = (base + Double.random(in: -180...220, using: &rng)).rounded()
            let units = (amount / 4.95).rounded()
            make(shop: "การไฟฟ้านครหลวง (MEA)", date: at(day, hour: 18), kind: .electricity, units: units,
                 items: [("ค่าไฟฟ้า", 1, amount, .utilities)], in: context)
        }
        if dayOfMonth == 15 {
            let amount = (Double.random(in: 260...380, using: &rng)).rounded()
            make(shop: "การประปานครหลวง (MWA)", date: at(day, hour: 18), kind: .water, units: (amount / 12.5).rounded(),
                 items: [("ค่าน้ำประปา", 1, amount, .utilities)], in: context)
        }
        if dayOfMonth == 5 {
            make(shop: "AIS Fibre", date: at(day, hour: 9), kind: .internet,
                 items: [("อินเทอร์เน็ตไฟเบอร์ 1Gbps", 1, 748, .utilities)], in: context)
        }
    }

    private static func insert(_ shop: Shop, on day: Date, now: Date, rng: inout SeededGenerator, in context: ModelContext) {
        let hour = Int.random(in: shop.hours, using: &rng)
        let date = Calendar.app.date(bySettingHour: hour, minute: Int.random(in: 0...59, using: &rng), second: 0, of: day)!
        guard date <= now else { return }

        var items: [(String, Double, Double, SpendCategory)] = []
        if let range = shop.priceRange, let product = shop.products.first {
            items = [(product.name, 1, Double.random(in: range, using: &rng).rounded(), product.category)]
        } else {
            let count = min(Int.random(in: shop.items, using: &rng), shop.products.count)
            for product in shop.products.shuffled(using: &rng).prefix(count) {
                let quantity = Double(Int.random(in: 1...shop.maxQuantity, using: &rng))
                items.append((product.name, quantity, product.price * quantity, product.category))
            }
        }
        let fullInvoice = Double.random(in: 0..<1, using: &rng) < shop.fullTaxInvoiceChance
        make(shop: shop.name, date: date, isFullTaxInvoice: fullInvoice, items: items, in: context)
    }

    private static func make(
        shop: String,
        date: Date,
        kind: ReceiptKind = .purchase,
        isFullTaxInvoice: Bool = false,
        units: Double = 0,
        items: [(String, Double, Double, SpendCategory)],
        in context: ModelContext
    ) {
        let total = items.reduce(0) { $0 + $1.2 }
        let receipt = Receipt(
            shopName: shop,
            date: date,
            total: total,
            vat: ThaiTax.vatIncluded(in: total),
            kind: kind,
            isFullTaxInvoice: isFullTaxInvoice,
            billUnits: units,
            reader: "Sample"
        )
        context.insert(receipt)
        for (index, item) in items.enumerated() {
            let line = LineItem(name: item.0, quantity: item.1, total: item.2, category: item.3, position: index)
            context.insert(line)
            line.receipt = receipt
        }
    }

    private static func at(_ day: Date, hour: Int) -> Date {
        Calendar.app.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }
}

/// Deterministic random numbers so the sample data is the same on every device.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}
