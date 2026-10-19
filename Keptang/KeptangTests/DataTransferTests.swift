import Foundation
import SwiftData
import Testing
@testable import Keptang

@Suite("Import and export")
@MainActor
struct DataTransferTests {
    func makeContext() throws -> ModelContext {
        ModelContext(try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self,
                                        configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    func seed(_ context: ModelContext) {
        let date = Calendar.app.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12, minute: 30))!
        let lunch = Receipt(shopName: "Café, \"Amazon\"", date: date, total: 125, vat: 8.18, kind: .purchase, isFullTaxInvoice: true,
                            reader: "Typed", imageData: Data([1, 2, 3]))
        context.insert(lunch)
        for (index, item) in [("latte", 65.0), ("cake", 60.0)].enumerated() {
            let line = LineItem(name: item.0, total: item.1, category: .dining, position: index)
            context.insert(line)
            line.receipt = lunch
        }
        let pay = Receipt(shopName: "เงินเดือน", date: date.addingTimeInterval(3600), total: 30_000, vat: 0, kind: .purchase,
                          isFullTaxInvoice: false, reader: "Typed")
        pay.isIncome = true
        pay.incomeSource = .salary
        context.insert(pay)
        try? context.save()
    }

    @Test("A backup brings everything back on an empty device, and importing twice adds nothing")
    func backupRoundTrip() throws {
        let source = try makeContext()
        seed(source)
        let defaults = UserDefaults(suiteName: "DataTransferTests.backup")!
        defaults.removePersistentDomain(forName: "DataTransferTests.backup")
        let all = try source.fetch(FetchDescriptor<Receipt>())
        let data = try DataTransfer.encode(DataTransfer.backup(of: all, includePhotos: true, defaults: defaults))

        let target = try makeContext()
        let first = try DataTransfer.importFile(data, into: target, defaults: defaults)
        #expect(first == .init(added: 2, skipped: 0, unreadable: 0))
        let back = try target.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date)]))
        #expect(back[0].shopName == "Café, \"Amazon\"")
        #expect(back[0].sortedItems.map(\.name) == ["latte", "cake"])
        #expect(back[0].imageData == Data([1, 2, 3]))
        #expect(back[0].isFullTaxInvoice)
        #expect(back[1].isIncome && back[1].incomeSource == .salary)

        let again = try DataTransfer.importFile(data, into: target, defaults: defaults)
        #expect(again == .init(added: 0, skipped: 2, unreadable: 0))
    }

    @Test("The spreadsheet export reads back in, money in and out kept apart")
    func csvRoundTrip() throws {
        let source = try makeContext()
        seed(source)
        let csv = DataTransfer.csv(of: try source.fetch(FetchDescriptor<Receipt>()))
        #expect(csv.hasPrefix("Date,Time,Shop,In or out"))
        #expect(csv.contains("\"Café, \"\"Amazon\"\"\""))
        #expect(csv.contains("-125.00"))

        let target = try makeContext()
        let result = try DataTransfer.importFile(Data(csv.utf8), into: target)
        #expect(result.added == 2)
        let back = try target.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date)]))
        #expect(back[0].shopName == "Café, \"Amazon\"" && back[0].total == 125 && !back[0].isIncome)
        #expect(back[0].sortedItems.map(\.name) == ["latte", "cake"])
        #expect(back[0].mainCategory == .dining)
        #expect(back[1].isIncome && back[1].total == 30_000)
    }

    @Test("A bank's CSV: Thai dates and Buddhist years, negative money out, amounts with commas")
    func bankCSV() throws {
        let bank = """
        Date,Description,Amount
        17/10/2569,GRAB TAXI,-120.00
        18/10/2569,Salary Oct,"30,000.00"
        19/10/2026,7-Eleven,(45.50)
        not a date,Broken,10
        """
        let context = try makeContext()
        let result = try DataTransfer.importCSV(bank, into: context)
        #expect(result == .init(added: 3, skipped: 0, unreadable: 1))
        let rows = try context.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date)]))
        #expect(Calendar.app.component(.year, from: rows[0].date) == 2026)
        #expect(!rows[0].isIncome && rows[0].total == 120 && rows[0].mainCategory == .transport)
        #expect(rows[1].isIncome && rows[1].total == 30_000)
        #expect(!rows[2].isIncome && rows[2].total == 45.5)
    }

    @Test("Files that aren't backups or spreadsheets say so")
    func unknown() throws {
        let context = try makeContext()
        #expect(throws: DataTransfer.ImportError.self) { try DataTransfer.importFile(Data("{\"hello\": 1}".utf8), into: context) }
        #expect(throws: DataTransfer.ImportError.self) { try DataTransfer.importFile(Data("just some words".utf8), into: context) }
    }
}
