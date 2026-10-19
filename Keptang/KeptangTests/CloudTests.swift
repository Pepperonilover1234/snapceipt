import Foundation
import SwiftData
import Testing
@testable import Keptang

@Suite("Chat bot inbox")
struct CloudTests {
    /// A row as Supabase sends it: six-digit fractions and a +00:00 offset.
    let json = """
    [{"id":"7d1c","user_id":"u1","origin":"discord","kind":"text","raw_text":"Pop corn 60","photo_path":null,
      "parsed":{"flow":"moneyOut","items":[{"name":"pop corn","amount":60,"category":"entertainment"}],"source":"other",
                "date":"2026-10-17T05:00:00.000Z","language":"English"},
      "status":"confirmed","created_at":"2026-10-18T11:30:00.123456+00:00"},
     {"id":"9a2b","user_id":"u1","origin":"discord","kind":"text","raw_text":"เงินเดือน 30000","photo_path":null,
      "parsed":{"flow":"moneyIn","items":[{"name":"เงินเดือน","amount":30000,"category":"other"}],"source":"salary",
                "date":"2026-10-18T11:31:00.000Z","language":"Thai"},
      "status":"confirmed","created_at":"2026-10-18T11:31:00+00:00"},
     {"id":"p1","user_id":"u1","origin":"discord","kind":"photo","raw_text":"lunch","photo_path":"u1/p1.jpg","parsed":null,
      "status":"pending","created_at":"2026-10-18T11:32:00.5+00:00"}]
    """

    @Test("Rows decode, dates and all")
    func decoding() throws {
        let rows = try JSONDecoder().decode([InboxRow].self, from: Data(json.utf8))
        #expect(rows.count == 3)
        #expect(rows[2].photoPath == "u1/p1.jpg")
        #expect(rows[0].created == ISO8601DateFormatter().date(from: "2026-10-18T11:30:00Z"))
        #expect(rows[2].created == ISO8601DateFormatter().date(from: "2026-10-18T11:32:00Z"))
    }

    @Test("A checked chat entry becomes the same entry Type it would save")
    func entries() throws {
        let rows = try JSONDecoder().decode([InboxRow].self, from: Data(json.utf8))
        let out = try #require(CloudSync.entry(from: rows[0]))
        #expect(out.flow == .moneyOut)
        #expect(out.items.first?.category == .entertainment)
        #expect(out.total == 60)
        #expect(out.date == ISO8601DateFormatter().date(from: "2026-10-17T05:00:00Z"))
        let pay = try #require(CloudSync.entry(from: rows[1]))
        #expect(pay.flow == .moneyIn)
        #expect(pay.source == .salary)
        #expect(pay.total == 30_000)
        #expect(CloudSync.entry(from: rows[2]) == nil, "photos are read on the phone, not imported as text")
    }

    @Test("Saving it keeps money in apart and marks where it came from")
    @MainActor
    func saving() throws {
        let container = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let rows = try JSONDecoder().decode([InboxRow].self, from: Data(json.utf8))
        let learner = CategoryLearner(defaults: UserDefaults(suiteName: "CloudTests")!, loadModel: false)
        let spent = QuickEntryStore.save(try #require(CloudSync.entry(from: rows[0])), in: context, learner: learner)
        let paid = QuickEntryStore.save(try #require(CloudSync.entry(from: rows[1])), in: context, learner: learner)
        #expect(!spent.isIncome && spent.items.first?.category == .entertainment)
        #expect(paid.isIncome && paid.incomeSource == .salary && paid.items.isEmpty)
    }

    @Test("The shared summary has this month's totals only")
    @MainActor
    func summary() throws {
        let container = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let calendar = Calendar.app
        let now = calendar.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 18))!
        func add(_ shop: String, _ amount: Double, _ category: SpendCategory, day: Int, month: Int = 10, income: Bool = false) {
            let date = calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
            let receipt = Receipt(shopName: shop, date: date, total: amount, vat: 0, kind: .purchase, isFullTaxInvoice: false, reader: "Test")
            receipt.isIncome = income
            context.insert(receipt)
            if !income {
                let line = LineItem(name: shop, total: amount, category: category, position: 0)
                context.insert(line)
                line.receipt = receipt
            }
        }
        add("Lunch", 300, .dining, day: 3)
        add("BTS", 100, .transport, day: 5)
        add("Old", 999, .shopping, day: 20, month: 9)
        add("Salary", 30_000, .other, day: 1, income: true)
        try context.save()
        let all = try context.fetch(FetchDescriptor<Receipt>())
        let s = CloudSync.summary(of: all, goal: 1_000, now: now)
        #expect(s.month == "2026-10-01")
        #expect(s.spent == 400)
        #expect(s.income == 30_000)
        #expect(s.byCategory.map(\.category) == ["dining", "transport"])
        #expect(s.daysLeft == 15)
        #expect(abs(s.perDay - 40) < 0.01)
    }
}
