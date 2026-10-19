import Foundation
import Testing
@testable import Keptang

@Suite("Typing an entry")
struct QuickEntryTests {
    let now = Calendar.app.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 18, minute: 30))!
    /// No saved corrections and no Create ML model, so only the rules decide.
    let learner = CategoryLearner(defaults: UserDefaults(suiteName: "QuickEntryTests")!, loadModel: false)

    func read(_ text: String) -> QuickEntry { QuickEntryRules.read(text, now: now, learner: learner) }

    @Test("“Pop corn 60” is ฿60 spent on entertainment today")
    func popcorn() {
        let entry = read("Pop corn 60")
        #expect(entry.flow == .moneyOut)
        #expect(entry.items.count == 1)
        #expect(entry.items[0].name == "pop corn")
        #expect(entry.items[0].amount == 60)
        #expect(entry.items[0].category == .entertainment)
        #expect(Calendar.app.isDate(entry.date, inSameDayAs: now))
        #expect(entry.language == "English")
    }

    @Test("Thai works the same way")
    func thai() {
        let entry = read("ป๊อปคอร์น 60 บาท")
        #expect(entry.flow == .moneyOut)
        #expect(entry.items.first?.name == "ป๊อปคอร์น")
        #expect(entry.items.first?.amount == 60)
        #expect(entry.items.first?.category == .entertainment)
        #expect(entry.language == "Thai")
        let rice = read("ข้าวมันไก่ 50 เมื่อวาน")
        #expect(rice.items.first?.category == .dining)
        #expect(Calendar.app.isDate(rice.date, inSameDayAs: Calendar.app.date(byAdding: .day, value: -1, to: now)!))
    }

    @Test("Income words and a plus sign mean money in")
    func income() {
        let pay = read("เงินเดือน 30000")
        #expect(pay.flow == .moneyIn)
        #expect(pay.source == .salary)
        #expect(pay.total == 30_000)
        let sold = read("+500 sold old shoes")
        #expect(sold.flow == .moneyIn)
        #expect(sold.source == .sales)
        #expect(sold.total == 500)
        #expect(read("refund 250").source == .refund)
        #expect(read("salary 45k").total == 45_000)
    }

    @Test("A pharmacy is a shop, not a sale")
    func pharmacy() {
        let entry = read("ร้านขายยา 120")
        #expect(entry.flow == .moneyOut)
    }

    @Test("Several things, split at commas and “and” when each has a price")
    func severalItems() {
        let two = read("coffee 45, cake 80")
        #expect(two.items.map(\.amount) == [45, 80])
        #expect(two.items.map(\.category) == [.dining, .dining])
        #expect(two.total == 125)
        let joined = read("coffee and cake 125")
        #expect(joined.items.count == 1)
        #expect(joined.items[0].amount == 125)
        let anded = read("grab 120 and popcorn 60 yesterday")
        #expect(anded.items.map(\.amount) == [120, 60])
        #expect(anded.items.map(\.category) == [.transport, .entertainment])
        #expect(Calendar.app.isDateInYesterday(anded.date) || !Calendar.app.isDate(anded.date, inSameDayAs: now))
    }

    @Test("Amounts with commas, decimals and k")
    func amounts() {
        #expect(read("shoes 1,290").total == 1_290)
        #expect(read("latte 65.50").total == 65.5)
        #expect(read("iphone 1.5k").total == 1_500)
        #expect(read("7-eleven 45").total == 45)
        #expect(read("lunch").total == 0)
    }
}

@Suite("VAT lines on scanned receipts")
struct VATLineTests {
    @Test("“VAT 7% incl.” is the VAT, not something bought; “Amount incl. VAT” is not the VAT")
    func vatLines() {
        #expect(ReceiptRules.isVATLine("vat 7% incl.   23.55"))
        #expect(ReceiptRules.isVATLine("vat 7%  23.55"))
        #expect(!ReceiptRules.isVATLine("amount incl. vat  360.00"))
        #expect(!ReceiptRules.isVATLine("vatable  336.45"))
    }
}
