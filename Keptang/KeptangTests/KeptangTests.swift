import AVFoundation
import Foundation
import SwiftData
import Testing
@testable import Keptang

// MARK: - Helpers

private let calendar = Calendar.app

private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

/// A fixed "now", so tests don't depend on when they run.
private let now = date(2026, 10, 17, 18, 30)

private func purchase(_ when: Date, _ total: Double, _ items: [(SpendCategory, Double)] = [], shop: String = "Shop") -> ReceiptSnapshot {
    ReceiptSnapshot(date: when, total: total, shop: shop, items: items.isEmpty ? [(.groceries, total)] : items.map { ($0.0, $0.1) })
}

/// About 14 months of varied spending: one to three receipts most days, a bill each month.
private func history() -> [ReceiptSnapshot] {
    var receipts: [ReceiptSnapshot] = []
    var seed: UInt64 = 42
    func next() -> Double {
        seed = seed &* 6364136223846793005 &+ 1442695040888963407
        return Double(seed >> 33) / Double(1 << 31)
    }
    var day = date(2025, 8, 1, 0)
    while day < now {
        let count = Int(next() * 3)
        for index in 0..<count {
            let when = calendar.date(byAdding: .minute, value: 7 * 60 + Int(next() * 14 * 60) + index, to: day)!
            if when >= now { continue }
            let total = (20 + next() * 900).roundedToSatang()
            receipts.append(purchase(when, total, [(.dining, total * 0.6), (.groceries, total * 0.3)], shop: "Shop \(index)"))
        }
        if calendar.component(.day, from: day) == 20 {
            receipts.append(ReceiptSnapshot(date: day.addingTimeInterval(18 * 3600), total: 2_400, kind: .electricity,
                                            items: [(.other, 2_400)]))
        }
        day = calendar.date(byAdding: .day, value: 1, to: day)!
    }
    return receipts
}

private func isClose(_ a: Double, _ b: Double) -> Bool { abs(a - b) < 0.005 }

private func freshLearner() -> CategoryLearner {
    let suite = "KeptangTests-\(UUID().uuidString)"
    return CategoryLearner(defaults: UserDefaults(suiteName: suite)!, loadModel: false)
}

// MARK: - Periods and paging

@Suite("Spending periods")
struct PeriodTests {
    @Test("Pages tile with no gap or overlap", arguments: TimeRange.allCases)
    func pagesTile(range: TimeRange) {
        for offset in -12...0 {
            let earlier = range.interval(offset: offset - 1, now: now)
            let later = range.interval(offset: offset, now: now)
            #expect(earlier.end == later.start, "\(range.rawValue) page \(offset)")
        }
    }

    @Test("Chart points add up to the period total on every page", arguments: TimeRange.allCases)
    func pointsSumToTotal(range: TimeRange) {
        let analyzer = SpendingAnalyzer(history())
        for offset in -3...0 {
            let interval = range.interval(offset: offset, now: now)
            let points = analyzer.points(for: range, now: now, offset: offset)
            let sum = points.reduce(0) { $0 + $1.amount }
            #expect(isClose(sum, analyzer.total(in: interval)), "\(range.rawValue) page \(offset)")
            #expect(points.first?.date == interval.start)
            #expect(isClose(points.last?.cumulative ?? 0, sum))
        }
    }

    @Test("Twelve 1M pages count every receipt in them exactly once")
    func monthPagesCountOnce() {
        let receipts = history()
        let analyzer = SpendingAnalyzer(receipts)
        let pages = (-11...0).map { TimeRange.month.interval(offset: $0, now: now) }
        let paged = pages.reduce(0) { $0 + analyzer.total(in: $1) }
        let whole = DateInterval(start: pages.first!.start, end: pages.last!.end)
        let direct = receipts.filter { whole.contains($0.date) && $0.date < whole.end }.reduce(0) { $0 + $1.total }
        #expect(isClose(paged, direct))
        #expect(isClose(paged, analyzer.total(in: whole)))
    }

    @Test("1Y points are the calendar months of this year, up to now")
    func yearIsMonthly() {
        let receipts = history()
        let analyzer = SpendingAnalyzer(receipts)
        let points = analyzer.points(for: .year, now: now)
        #expect(points.count == 10, "January to October; November and December are still to come")
        #expect(calendar.component(.month, from: points.first!.date) == 1)
        for point in points {
            let month = calendar.dateInterval(of: .month, for: point.date)!
            #expect(month.start == point.date)
            let expected = receipts.filter { $0.date >= month.start && $0.date < month.end }.reduce(0) { $0 + $1.total }
            #expect(isClose(point.amount, expected))
        }
        #expect(calendar.component(.month, from: points.last!.date) == 10)
    }

    @Test("The earliest page is the one holding the first receipt")
    func earliestPage() {
        let analyzer = SpendingAnalyzer([purchase(date(2026, 8, 1), 100), purchase(date(2026, 10, 10), 50)])
        let offset = analyzer.earliestOffset(for: .month, now: now)
        #expect(TimeRange.month.interval(offset: offset, now: now).contains(date(2026, 8, 1)))
        #expect(!TimeRange.month.interval(offset: offset + 1, now: now).contains(date(2026, 8, 1)))
        #expect(SpendingAnalyzer([]).earliestOffset(for: .month, now: now) == 0)
    }

    @Test("A bucket's receipts add up to the bucket's point")
    func bucketReceipts() {
        let analyzer = SpendingAnalyzer(history())
        for point in analyzer.points(for: .week, now: now) {
            let inside = analyzer.receipts(in: TimeRange.week.bucket(startingAt: point.date))
            #expect(inside.count == point.count)
            #expect(isClose(inside.reduce(0) { $0 + $1.total }, point.amount))
        }
    }
}

// MARK: - Categories and counting

@Suite("Category totals")
struct CategoryTotalTests {
    @Test("Categories always add up to the amount paid")
    func splitMatchesTotal() {
        // Items add up to ฿120 but ฿100 was paid after a discount the scan missed.
        let missed = ReceiptSnapshot(date: now, total: 100, items: [(.dining, 80), (.groceries, 40)])
        #expect(isClose(missed.categoryAmounts.values.reduce(0, +), 100))
        #expect(isClose(missed.categoryAmounts[.dining]!, 100 * 80 / 120))

        // A discount line on the receipt.
        let discounted = ReceiptSnapshot(date: now, total: 95, items: [(.groceries, 100), (.groceries, -5)])
        #expect(discounted.categoryAmounts == [.groceries: 95])

        // No items at all.
        let bare = ReceiptSnapshot(date: now, total: 42, items: [])
        #expect(bare.categoryAmounts == [.other: 42])
    }

    @Test("Category totals equal spending for the period")
    func analyzerCategoryTotals() {
        let analyzer = SpendingAnalyzer(history())
        for range in TimeRange.allCases {
            let interval = range.interval(offset: 0, now: now)
            let byCategory = analyzer.categoryTotals(in: interval).reduce(0) { $0 + $1.amount }
            #expect(isClose(byCategory, analyzer.total(in: interval)), "\(range.rawValue)")
        }
    }

    @Test("Bills always count as Utilities", arguments: ReceiptKind.billKinds)
    func billsAreUtilities(kind: ReceiptKind) {
        let bill = ReceiptSnapshot(date: now, total: 812.5, kind: kind, items: [(.other, 500), (.shopping, 312.5)])
        #expect(bill.categoryAmounts == [.utilities: 812.5])
    }

    @Test("Saved categories keep their stored values")
    func rawValuesAreStable() {
        let stored = ["groceries", "dining", "transport", "shopping", "health", "home", "utilities", "entertainment", "other"]
        for raw in stored { #expect(SpendCategory(rawValue: raw) != nil, "\(raw)") }
        #expect(SpendCategory.home.name == "Home")
        #expect(!SpendCategory.selectable.contains(.home))
        #expect(SpendCategory.selectable.map(\.name) == [
            "Food & Drinks", "Groceries", "Utilities", "Transportation", "Shopping", "Health", "Entertainment",
            "Subscriptions", "Education", "Other",
        ])
    }
}

@Suite("Automatic categories")
struct MerchantTests {
    @Test("Merchants are recognised", arguments: [
        ("Lotus's", MerchantCategorizer.MerchantType.supermarket),
        ("ตลาดดี ซูเปอร์มาร์เก็ต", .supermarket),
        ("7-Eleven", .supermarket),
        ("Big C Extra", .supermarket),
        ("Tops Market", .supermarket),
        ("ร้านอาหาร ครัวบ้านสวน", .restaurant),
        ("Café Amazon", .restaurant),
        ("Bar B Q Plaza", .restaurant),
        ("MK Restaurants", .restaurant),
        ("ฟู้ดคอร์ท อาคารสำนักงาน", .restaurant),
        ("GrabFood", .restaurant),
        ("Grab", .transport),
        ("BTS Skytrain", .transport),
        ("PTT Station", .transport),
        ("Netflix", .subscription),
        ("Spotify AB", .subscription),
        ("Chulalongkorn University", .education),
        ("SE-ED Book Center", .education),
        ("Major Cineplex", .entertainment),
        ("Boots", .health),
        ("โรงพยาบาลกรุงเทพ", .health),
        ("การไฟฟ้านครหลวง (MEA)", .utility),
        ("การประปานครหลวง (MWA)", .utility),
    ])
    func recognises(shop: String, type: MerchantCategorizer.MerchantType) {
        #expect(MerchantCategorizer.merchantType(for: shop) == type)
    }

    @Test("Short names only match whole words")
    func wholeWords() {
        #expect(MerchantCategorizer.merchantType(for: "Topshop") == nil)
        #expect(MerchantCategorizer.merchantType(for: "Smk Hardware") == nil)
        #expect(MerchantCategorizer.merchantType(for: "") == nil)
    }

    @Test("Items take the merchant's category where the shop sells one kind of thing")
    func strongMerchants() {
        let learner = freshLearner()
        func category(_ item: String, at shop: String) -> SpendCategory {
            MerchantCategorizer.category(forItem: item, shopName: shop, aiGuess: nil, learner: learner)
        }
        #expect(category("ข้าวผัดกุ้ง", at: "ร้านอาหาร ครัวบ้านสวน") == .dining)
        #expect(category("Coke", at: "KFC") == .dining)
        #expect(category("Standard plan", at: "Netflix") == .subscriptions)
        #expect(category("Monthly fee", at: "Spotify") == .subscriptions)
        #expect(category("Term 2", at: "โรงเรียนกวดวิชา") == .education)
        #expect(category("Ticket", at: "Major Cineplex") == .entertainment)
        #expect(category("Paracetamol", at: "Watsons") == .health)
        #expect(category("Gasohol 95", at: "Shell") == .transport)
        #expect(category("ค่าพลังงานไฟฟ้า", at: "การไฟฟ้านครหลวง") == .utilities)
    }

    @Test("Supermarket items default to Groceries but keep a clear guess")
    func supermarkets() {
        let learner = freshLearner()
        func category(_ item: String) -> SpendCategory {
            MerchantCategorizer.category(forItem: item, shopName: "Lotus's", aiGuess: nil, learner: learner)
        }
        #expect(category("Mystery item 123") == .groceries)
        #expect(category("นมจืด เมจิ 2 ลิตร") == .groceries)
        #expect(category("ยาสีฟัน คอลเกต") == .health)
        #expect(category("Unknown thing at a hardware shop") == .groceries)
        #expect(MerchantCategorizer.category(forItem: "Mystery item 123", shopName: "Hardware House", aiGuess: nil, learner: learner) == .other)
    }

    @Test("New guesses never use the legacy Home category")
    func noLegacyGuesses() {
        let learner = freshLearner()
        #expect(learner.guess(for: "น้ำยาล้างจาน", aiGuess: nil) == .shopping)
        #expect(learner.guess(for: "Anything", aiGuess: .home) == .shopping)
    }

    @Test("The person's corrections win")
    func corrections() {
        let learner = freshLearner()
        learner.learn("Coke", as: .groceries)
        #expect(MerchantCategorizer.category(forItem: "coke ", shopName: "KFC", aiGuess: nil, learner: learner) == .groceries)

        learner.learnMerchant("Café Amazon", as: .shopping)
        #expect(MerchantCategorizer.category(forItem: "Latte", shopName: "cafe amazon", aiGuess: nil, learner: learner) == .shopping)
        #expect(learner.learnedCount == 1)
    }

    @Test("Bills and adjustments on a scanned receipt")
    func finalize() {
        var bill = ParsedReceipt()
        bill.shopName = "การไฟฟ้านครหลวง"
        bill.kind = .electricity
        bill.total = 2_424.25
        bill.items = [ParsedItem(name: "ค่าพลังงานไฟฟ้า", total: 2_034.39), ParsedItem(name: "VAT 7%", total: 158.6)]
        ReceiptReader.finalize(&bill)
        #expect(bill.items.allSatisfy { $0.category == .utilities })

        var water = ParsedReceipt()
        water.shopName = "การประปานครหลวง (MWA)"
        water.total = 289
        water.items = [ParsedItem(name: "ค่าน้ำประปา", total: 270.09)]
        ReceiptReader.finalize(&water)
        #expect(water.items.allSatisfy { $0.category == .utilities })
    }
}

// MARK: - Duplicates and search

@Suite("Duplicates and search")
struct MatchingTests {
    let saved = [
        DuplicateCheck.Candidate(shop: "Lotus's", total: 894, date: date(2026, 10, 17, 13, 42)),
        DuplicateCheck.Candidate(shop: "Café Amazon", total: 70, date: date(2026, 10, 16, 0, 0)),
    ]

    @Test("The same receipt scanned again is caught")
    func caught() {
        #expect(DuplicateCheck.firstMatch(shop: "LOTUS'S", total: 894.004, date: date(2026, 10, 17, 13, 47), among: saved) == 0)
        // No printed time: any time that day.
        #expect(DuplicateCheck.firstMatch(shop: "cafe amazon", total: 70, date: date(2026, 10, 16, 0, 0), among: saved) == 1)
        #expect(DuplicateCheck.firstMatch(shop: "Café Amazon", total: 70, date: date(2026, 10, 16, 9, 52), among: saved) == 1)
    }

    @Test("Different purchases are not duplicates")
    func notCaught() {
        #expect(DuplicateCheck.firstMatch(shop: "Lotus's", total: 894, date: date(2026, 10, 17, 14, 0), among: saved) == nil)
        #expect(DuplicateCheck.firstMatch(shop: "Lotus's", total: 895, date: date(2026, 10, 17, 13, 42), among: saved) == nil)
        #expect(DuplicateCheck.firstMatch(shop: "Big C", total: 894, date: date(2026, 10, 17, 13, 42), among: saved) == nil)
        #expect(DuplicateCheck.firstMatch(shop: "Café Amazon", total: 70, date: date(2026, 10, 17, 0, 0), among: saved) == nil)
    }

    private let fields = ReceiptSearch.Fields(
        shop: "ตลาดดี ซูเปอร์มาร์เก็ต",
        rawText: "TALADDEE SUPERMARKET CO., LTD.\nTAX ID 0105560000017\nยอดสุทธิ / TOTAL 894.00",
        total: 894,
        categories: [.groceries, .health],
        items: [("อกไก่ ซีพี 1 กก", 129), ("ยาสีฟัน คอลเกต", 89.5)]
    )

    @Test("Search finds shop, items, photo text, categories and amounts", arguments: [
        "ตลาดดี", "อกไก่", "0105560000017", "taladdee", "groceries", "Health", "สุขภาพ", "894", "฿894.00", "129", "89.50", "89",
    ])
    func finds(query: String) {
        #expect(ReceiptSearch.matches(query, fields))
    }

    @Test("Search leaves out what isn't there", arguments: ["Netflix", "130", "89.49", "Education"])
    func misses(query: String) {
        #expect(!ReceiptSearch.matches(query, fields))
    }
}

// MARK: - Calendar

@Suite("Spending calendar")
struct CalendarTests {
    @Test("Daily totals split at midnight, including the end of a month")
    func dailyTotals() {
        let receipts = [
            purchase(date(2026, 9, 30, 23, 59), 100),
            purchase(date(2026, 10, 1, 0, 0), 40),
            purchase(date(2026, 10, 1, 21, 15), 60),
            ReceiptSnapshot(date: date(2026, 10, 20, 18), total: 2_400, kind: .electricity, items: []),
        ]
        let analyzer = SpendingAnalyzer(receipts)
        let october = analyzer.month(containing: date(2026, 10, 15))
        let days = analyzer.dailyTotals(in: october)
        #expect(days.count == 2)
        #expect(days[date(2026, 10, 1, 0)] == DayTotal(day: date(2026, 10, 1, 0), total: 100, count: 2))
        #expect(days[date(2026, 10, 20, 0)]?.total == 2_400)
        #expect(days.values.reduce(0) { $0 + $1.total } == analyzer.total(in: october))

        let september = analyzer.dailyTotals(in: analyzer.month(containing: date(2026, 9, 2)))
        #expect(september[date(2026, 9, 30, 0)]?.total == 100)
    }

    @Test("Maths uses the Gregorian calendar whatever the phone shows")
    func buddhistCalendar() {
        #expect(Calendar.app.identifier == .gregorian)
        var buddhist = Calendar(identifier: .buddhist)
        buddhist.timeZone = Calendar.app.timeZone
        let day = date(2026, 10, 17, 10)
        // Thai phones show 2569, but months and days line up with the Gregorian ones.
        #expect(buddhist.component(.year, from: day) == 2569)
        #expect(buddhist.dateInterval(of: .month, for: day) == Calendar.app.dateInterval(of: .month, for: day))
        #expect(buddhist.startOfDay(for: day) == Calendar.app.startOfDay(for: day))
    }

    @Test("Calendar days add up to the month for every month of the year")
    func monthsAddUp() {
        let analyzer = SpendingAnalyzer(history())
        for back in 0..<12 {
            let month = analyzer.month(containing: calendar.date(byAdding: .month, value: -back, to: now)!)
            let days = analyzer.dailyTotals(in: month)
            #expect(isClose(days.values.reduce(0) { $0 + $1.total }, analyzer.total(in: month)))
            #expect(days.keys.allSatisfy { month.contains($0) })
        }
    }
}

// MARK: - Permanent storage

@Suite("Permanent storage")
@MainActor
struct StorageTests {
    @Test("Receipts, photos, read text and items survive reopening the store")
    func roundTrip() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("KeptangTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("store.sqlite")
        let photo = Data((0..<300_000).map { UInt8(truncatingIfNeeded: $0 &* 31) })
        let twoYearsAgo = calendar.date(byAdding: .year, value: -2, to: now)!

        do {
            let container = try ModelContainer(for: Receipt.self, LineItem.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            var draft = ParsedReceipt()
            draft.shopName = "ตลาดดี ซูเปอร์มาร์เก็ต"
            draft.date = twoYearsAgo
            draft.total = 224
            draft.vat = 14.65
            draft.rawText = "TALADDEE SUPERMARKET\nยอดสุทธิ 224.00"
            draft.imageData = photo
            draft.items = [
                ParsedItem(name: "นมจืด", total: 95, category: .groceries),
                ParsedItem(name: "ยาสีฟัน", total: 129, category: .health),
            ]
            Receipt.insert(draft, into: context)
            try context.save()
        }

        let reopened = try ModelContainer(for: Receipt.self, LineItem.self, configurations: ModelConfiguration(url: url))
        let receipts = try ModelContext(reopened).fetch(FetchDescriptor<Receipt>())
        #expect(receipts.count == 1)
        let receipt = try #require(receipts.first)
        #expect(receipt.shopName == "ตลาดดี ซูเปอร์มาร์เก็ต")
        #expect(receipt.date == twoYearsAgo)
        #expect(receipt.total == 224)
        #expect(receipt.rawText.contains("ยอดสุทธิ"))
        #expect(receipt.imageData == photo)
        #expect(receipt.sortedItems.map(\.name) == ["นมจืด", "ยาสีฟัน"])
        #expect(receipt.sortedItems.map(\.category) == [.groceries, .health])
        // Older than the calendar's 12 months, and still counted and searchable.
        #expect(SpendingAnalyzer([ReceiptSnapshot(receipt)]).total(in: DateInterval(start: .distantPast, end: .distantFuture)) == 224)
        #expect(ReceiptSearch.matches("ยอดสุทธิ", receipt.searchFields))
    }
}

@Suite("Chart indicators")
struct IndicatorTests {
    @Test("One category's chart adds up to that category's total")
    func singleCategory() {
        let receipts = [
            ReceiptSnapshot(date: date(2026, 10, 10), total: 100, items: [(.dining, 60), (.groceries, 40)]),
            ReceiptSnapshot(date: date(2026, 10, 12), total: 50, items: [(.groceries, 50)]),
            ReceiptSnapshot(date: date(2026, 10, 14), total: 30, items: [(.dining, 30)]),
        ]
        let analyzer = SpendingAnalyzer(receipts)
        let dining = analyzer.only(.dining)
        let interval = TimeRange.month.interval(offset: 0, now: now)
        #expect(dining.total(in: interval) == 90)
        #expect(analyzer.only(.groceries).total(in: interval) == 90)
        #expect(dining.points(for: .month, now: now).reduce(0) { $0 + $1.amount } == 90)
        #expect(dining.points(for: .month, now: now).reduce(0) { $0 + $1.count } == 2)
        #expect(analyzer.only(.education).total(in: interval) == 0)
    }

    @Test("Moving average uses the period before for its first values")
    func movingAverage() {
        func points(_ amounts: [Double]) -> [SpendPoint] {
            amounts.enumerated().map { SpendPoint(date: date(2026, 10, 1 + $0.offset), amount: $0.element, cumulative: 0, count: 1) }
        }
        let average = SpendingAnalyzer.movingAverage(of: points([10, 20, 30]), previous: points([0, 0, 30]), window: 3)
        #expect(average == [40.0 / 3, 20, 20])
        #expect(SpendingAnalyzer.movingAverage(of: points([5]), previous: [], window: 7) == [5])
    }
}

@Suite("Candles")
struct CandleTests {
    // Monday 12 to Sunday 18 October; the period ends at 18:30 on the 17th, so 7D runs 11–17 Oct.
    let receipts = [
        purchase(date(2026, 10, 10, 9), 80),       // the day before the period: the first candle opens here
        purchase(date(2026, 10, 11, 9), 50),
        purchase(date(2026, 10, 11, 19), 150),     // 11 Oct: 200 from two receipts
        purchase(date(2026, 10, 12, 12), 120),     // 12 Oct: 120
        // 13 and 14 Oct: nothing
        purchase(date(2026, 10, 15, 8), 300),      // 15 Oct: 300
        purchase(date(2026, 10, 16, 8), 300),      // 16 Oct: 300, the same as the day before
    ]

    var points: [SpendPoint] { SpendingAnalyzer(receipts).points(for: .week, now: now) }

    @Test("A candle opens at the bucket before and closes at this one")
    func openClose() {
        let p = points
        #expect(p.count == 7)
        #expect(p.map(\.open) == [80, 200, 120, 0, 0, 300, 300])
        #expect(p.map(\.close) == [200, 120, 0, 0, 300, 300, 0])
        for (a, b) in zip(p, p.dropFirst()) { #expect(b.open == a.close) }
    }

    @Test("Up, down and flat")
    func rose() {
        let p = points
        #expect(p.map(\.rose) == [true, false, false, false, true, false, false])
        #expect(p[5].isFlat && !p[5].rose)
    }

    @Test("Two empty days in a row draw no candle; one after spending does")
    func emptyBuckets() {
        let p = points
        #expect(!p[2].isEmptyCandle, "12→13 Oct falls from 120 to 0")
        #expect(p[3].isEmptyCandle, "13→14 Oct, nothing either day")
        #expect(p[3].count == 0 && p[3].amount == 0)
    }

    @Test("The readout's high and low are the biggest and smallest receipt")
    func highLow() {
        let first = points[0]
        #expect(first.high == 150 && first.low == 50 && first.count == 2)
        #expect(points[3].high == 0 && points[3].low == 0)
    }

    @Test("Bodies span open to close, never below zero, and a flat day still shows")
    func body() {
        let p = points
        #expect(p[0].candleBody(minimumHeight: 5) == 80...200)
        #expect(p[1].candleBody(minimumHeight: 5) == 120...200)
        #expect(p[5].candleBody(minimumHeight: 5) == 300...305)
        #expect(p[2].candleBody(minimumHeight: 5).lowerBound == 0)
    }

    @Test("1Y candles are monthly totals, on the same scale as the 1Y bars")
    func yearScale() {
        let analyzer = SpendingAnalyzer(history())
        let p = analyzer.points(for: .year, now: now)
        for point in p { #expect(point.close == point.amount) }
        for (a, b) in zip(p, p.dropFirst()) { #expect(b.open == a.close) }
        let first = p[0]
        let before = Calendar.app.date(byAdding: .month, value: -1, to: first.date)!
        #expect(isClose(first.open, analyzer.total(in: DateInterval(start: before, end: first.date))))
    }
}

@Suite("Camera")
struct CameraTests {
    @Test("The scan button always knows what to do", arguments: [
        (true, AVAuthorizationStatus.authorized, CameraGate.open),
        (true, .notDetermined, .ask),
        (true, .denied, .denied),
        (true, .restricted, .restricted),
        (false, .authorized, .unavailable),
        (false, .notDetermined, .unavailable),
    ])
    func gate(supported: Bool, status: AVAuthorizationStatus, expected: CameraGate) {
        #expect(CameraGate.decide(isSupported: supported, status: status) == expected)
    }

    @Test("The app explains why it wants the camera")
    func usageDescription() {
        let text = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        #expect(text?.isEmpty == false)
    }
}

@Suite("Money goal")
struct MoneyGoalTests {
    let october = Calendar.app.dateInterval(of: .month, for: date(2026, 10, 1))!

    @Test("Progress, pace, left and per day")
    func maths() {
        let goal = MoneyGoal(goal: 10_000, spent: 6_200, month: october, now: date(2026, 10, 20, 9))
        #expect(goal.daysInMonth == 31 && goal.today == 20)
        #expect(isClose(goal.fraction, 0.62))
        #expect(isClose(goal.pace, 10_000 * 20 / 31))
        #expect(goal.left == 3_800)
        #expect(goal.daysLeft == 12)
        #expect(isClose(goal.perDay, 3_800 / 12))
        #expect(goal.state == .onPace)
        #expect(goal.spoken.hasPrefix("Money goal, 62 percent used"))
    }

    @Test("Ahead of pace and over the goal")
    func states() {
        #expect(MoneyGoal(goal: 10_000, spent: 5_000, month: october, now: date(2026, 10, 5)).state == .ahead)
        let over = MoneyGoal(goal: 10_000, spent: 12_500, month: october, now: date(2026, 10, 25))
        #expect(over.state == .over)
        #expect(over.overBy == 2_500 && over.left == 0 && over.perDay == 0)
        #expect(over.spoken.contains("over by"))
    }

    @Test("Month boundaries: first and last day, short months")
    func boundaries() {
        let first = MoneyGoal(goal: 3_100, spent: 0, month: october, now: date(2026, 10, 1, 0, 1))
        #expect(first.today == 1 && first.daysLeft == 31 && isClose(first.pace, 100))
        let last = MoneyGoal(goal: 3_100, spent: 3_100, month: october, now: date(2026, 10, 31, 23, 59))
        #expect(last.today == 31 && last.daysLeft == 1 && isClose(last.pace, 3_100) && last.state == .onPace)
        let february = Calendar.app.dateInterval(of: .month, for: date(2026, 2, 10))!
        #expect(MoneyGoal(goal: 2_800, spent: 0, month: february, now: date(2026, 2, 14)).daysInMonth == 28)
    }

    @Test("No goal means no progress, and the last-month preset rounds")
    func noGoal() {
        let none = MoneyGoal(goal: 0, spent: 500, month: october, now: date(2026, 10, 10))
        #expect(none.fraction == 0)
        #expect(MoneyGoal.suggestion(fromLastMonth: 0) == nil)
        #expect(MoneyGoal.suggestion(fromLastMonth: 28_640) == 29_000)
        #expect(MoneyGoal.suggestion(fromLastMonth: 300) == 1_000)
    }
}

@Suite("Type filter and search marks")
struct TypeAndSearchTests {
    @Test("Filtering by receipt type keeps only that type")
    func typeFilter() {
        let receipts = [
            purchase(date(2026, 10, 10), 120),
            ReceiptSnapshot(date: date(2026, 10, 12), total: 2_400, kind: .electricity, items: []),
            ReceiptSnapshot(date: date(2026, 10, 13), total: 300, kind: .water, items: []),
            ReceiptSnapshot(date: date(2026, 10, 14), total: 2_500, kind: .electricity, items: []),
        ]
        let all = SpendingAnalyzer(receipts)
        let month = TimeRange.month.interval(offset: 0, now: now)
        #expect(all.only(kind: .electricity).total(in: month) == 4_900)
        #expect(all.only(kind: .electricity).receipts(in: month).count == 2)
        #expect(all.only(kind: .purchase).total(in: month) == 120)
        #expect(all.only(kind: .internet).total(in: month) == 0)
        let byKind = ReceiptKind.allCases.reduce(0) { $0 + all.only(kind: $1).total(in: month) }
        #expect(byKind == all.total(in: month))
    }

    @Test("Search matches are found wherever they are, ignoring case")
    func ranges() {
        let text = "Café Amazon cafe AMAZON"
        let found = SearchHighlight.ranges(of: "amazon", in: text)
        #expect(found.count == 2)
        #expect(found.map { String(text[$0]) } == ["Amazon", "AMAZON"])
        #expect(SearchHighlight.ranges(of: "cafe", in: text).count == 2, "accents are ignored")
        #expect(SearchHighlight.ranges(of: "นม", in: "นมจืด เมจิ นม").count == 2)
        #expect(SearchHighlight.ranges(of: "", in: text).isEmpty)
        #expect(SearchHighlight.ranges(of: "xyz", in: text).isEmpty)
    }
}


@Suite("Calendar month and year ranges")
struct CalendarRangeTests {
    @Test("1M is the whole calendar month, 1Y the whole calendar year")
    func intervals() {
        let month = TimeRange.month.interval(offset: 0, now: now)
        #expect(month.start == date(2026, 10, 1, 0) && month.end == date(2026, 11, 1, 0))
        let year = TimeRange.year.interval(offset: 0, now: now)
        #expect(year.start == date(2026, 1, 1, 0) && year.end == date(2027, 1, 1, 0))
        let lastDay = TimeRange.month.interval(offset: 0, now: date(2026, 10, 31, 23, 59))
        #expect(lastDay == month)
        #expect(TimeRange.month.label(for: month) == month.start.formatted(.dateTime.month(.wide).year()))
    }

    @Test("February, leap years and the year boundary")
    func boundaries() {
        let feb2026 = TimeRange.month.interval(offset: 0, now: date(2026, 2, 14))
        #expect(calendar.dateComponents([.day], from: feb2026.start, to: feb2026.end).day == 28)
        let feb2028 = TimeRange.month.interval(offset: 0, now: date(2028, 2, 14))
        #expect(calendar.dateComponents([.day], from: feb2028.start, to: feb2028.end).day == 29)
        let january = date(2026, 1, 5)
        #expect(TimeRange.month.interval(offset: -1, now: january).start == date(2025, 12, 1, 0))
        #expect(TimeRange.year.interval(offset: -1, now: january).start == date(2025, 1, 1, 0))
    }

    @Test("Paging moves a whole month or year and the pages tile")
    func paging() {
        for back in 0..<14 {
            let later = TimeRange.month.interval(offset: -back, now: date(2026, 3, 31, 12))
            let earlier = TimeRange.month.interval(offset: -back - 1, now: date(2026, 3, 31, 12))
            #expect(earlier.end == later.start)
            #expect(calendar.component(.day, from: later.start) == 1)
        }
        #expect(TimeRange.year.interval(offset: -2, now: now).start == date(2024, 1, 1, 0))
    }

    @Test("An unfinished month or year is compared with the same stretch before")
    func partialComparison() {
        let month = TimeRange.month.comparison(offset: 0, now: now)
        #expect(month.start == date(2026, 9, 1, 0) && month.end == date(2026, 9, 18, 0), "1–17 Sep for 1–17 Oct")
        let year = TimeRange.year.comparison(offset: 0, now: now)
        #expect(year.start == date(2025, 1, 1, 0) && year.end == date(2025, 10, 18, 0))
        let endOfMarch = TimeRange.month.comparison(offset: 0, now: date(2026, 3, 31, 9))
        #expect(endOfMarch == DateInterval(start: date(2026, 2, 1, 0), end: date(2026, 3, 1, 0)), "all of a shorter February")
        // A finished month compares with the whole month before.
        #expect(TimeRange.month.comparison(offset: -1, now: now) == TimeRange.month.interval(offset: -2, now: now))
        #expect(TimeRange.week.comparison(offset: 0, now: now) == TimeRange.week.interval(offset: -1, now: now))
        #expect(TimeRange.month.comparisonLabel(month).hasPrefix("1–17"))
    }

    @Test("Days still to come are left out of the chart")
    func futureEmpty() {
        let analyzer = SpendingAnalyzer(history())
        let october = analyzer.points(for: .month, now: now)
        #expect(october.count == 17)
        #expect(october.allSatisfy { $0.date <= now })
        let september = analyzer.points(for: .month, now: now, offset: -1)
        #expect(september.count == 30)
    }
}

@Suite("Picking a period from the calendar")
struct PeriodPickingTests {
    // `now` is Saturday 17 October 2026, 18:30; that week runs Sunday 11 to Saturday 17 October.

    @Test("7D is the Sunday-to-Saturday week, the current one included")
    func sundayWeeks() {
        let week = TimeRange.week.interval(offset: 0, now: now)
        #expect(week.start == date(2026, 10, 11, 0) && week.end == date(2026, 10, 18, 0))
        let sunday = TimeRange.week.interval(offset: 0, now: date(2026, 10, 18, 9))
        #expect(sunday.start == date(2026, 10, 18, 0), "a Sunday starts a new week")
        #expect(TimeRange.week.interval(offset: -1, now: now).start == date(2026, 10, 4, 0))
        #expect(TimeRange.week.interval(offset: -1, now: now).end == week.start)
        let partial = TimeRange.week.comparison(offset: 0, now: date(2026, 10, 14, 12))
        #expect(partial == DateInterval(start: date(2026, 10, 4, 0), end: date(2026, 10, 8, 0)), "Sun–Wed against Sun–Wed")
        #expect(TimeRange.week.label(for: week).hasPrefix("11"))
    }

    @Test("1D is the calendar day, compared with yesterday up to the same hour")
    func calendarDay() {
        let today = TimeRange.day.interval(offset: 0, now: now)
        #expect(today == DateInterval(start: date(2026, 10, 17, 0), end: date(2026, 10, 18, 0)))
        #expect(TimeRange.day.interval(offset: -3, now: now).start == date(2026, 10, 14, 0))
        let before = TimeRange.day.comparison(offset: 0, now: now)
        #expect(before == DateInterval(start: date(2026, 10, 16, 0), end: date(2026, 10, 16, 19)))
    }

    @Test("Only Sundays can be picked for a week; any past day for a day")
    func sundayOnly() {
        let week = PeriodPicking(range: .week, now: now, firstReceipt: date(2026, 1, 7))
        #expect(week.isSelectable(day: date(2026, 10, 11)))
        for day in 12...17 { #expect(!week.isSelectable(day: date(2026, 10, day)), "\(day) Oct isn't a Sunday") }
        #expect(!week.isSelectable(day: date(2026, 10, 18)), "next week hasn't started")
        #expect(week.isSelectable(day: date(2026, 1, 4)), "the week holding the first receipt")
        #expect(!week.isSelectable(day: date(2025, 12, 28)), "before any receipt")
        let day = PeriodPicking(range: .day, now: now, firstReceipt: date(2026, 1, 7))
        #expect(day.isSelectable(day: date(2026, 10, 15)) && day.isSelectable(day: date(2026, 10, 17)))
        #expect(!day.isSelectable(day: date(2026, 10, 18)) && !day.isSelectable(day: date(2026, 1, 6)))
        #expect(week.grid(for: date(2026, 10, 1)).prefix(4).allSatisfy { $0 == nil }, "1 Oct 2026 is a Thursday")
    }

    @Test("Months and years stop at now and at the first receipt")
    func monthAndYearLimits() {
        let month = PeriodPicking(range: .month, now: now, firstReceipt: date(2025, 3, 20))
        #expect(month.isSelectable(month: date(2026, 10, 1)) && month.isSelectable(month: date(2025, 3, 1)))
        #expect(!month.isSelectable(month: date(2026, 11, 1)) && !month.isSelectable(month: date(2025, 2, 1)))
        let year = PeriodPicking(range: .year, now: now, firstReceipt: date(2024, 6, 1))
        #expect(year.years.map { calendar.component(.year, from: $0) } == [2024, 2025, 2026])
        #expect(PeriodPicking(range: .year, now: now, firstReceipt: nil).years.count == 1)
    }

    @Test("A picked date jumps to the page holding it")
    func jump() {
        let picks: [(TimeRange, Date)] = [(.day, date(2026, 10, 9)), (.week, date(2026, 9, 20)),
                                          (.month, date(2025, 12, 1)), (.year, date(2024, 1, 1))]
        for (range, picked) in picks {
            let offset = PeriodPicking(range: range, now: now, firstReceipt: date(2023, 1, 1)).offset(for: picked)
            #expect(range.interval(offset: offset, now: now).contains(picked), "\(range)")
            #expect(offset < 0)
        }
        #expect(PeriodPicking(range: .week, now: now, firstReceipt: nil).offset(for: date(2026, 10, 11)) == 0)
        #expect(TimeRange.week.offset(of: date(2026, 9, 20), now: now) == -3)
        #expect(TimeRange.month.offset(of: date(2025, 12, 1), now: now) == -10)
    }
}
