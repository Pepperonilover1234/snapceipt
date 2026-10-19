import Foundation
import SwiftData

/// Everything Snapceipt keeps, as one file: every receipt and income with its items (and, if asked,
/// its photo), plus the money goal and the category corrections. Importing it on another device
/// gives back the same history.
struct SnapceiptBackup: Codable, Equatable {
    static let formatName = "snapceipt-backup"

    struct Item: Codable, Equatable {
        var name: String
        var quantity: Double
        var total: Double
        var category: String
    }

    struct Entry: Codable, Equatable {
        var shop: String
        var date: Date
        var total: Double
        var vat: Double
        var kind: String
        var isFullTaxInvoice: Bool
        var sellerTaxID: String
        var billUnits: Double
        var reader: String
        var rawText: String
        var isIncome: Bool
        var incomeSource: String
        var items: [Item]
        /// The receipt photo as JPEG, only when the export asked for photos (base64 in the file).
        var photo: Data?
    }

    struct Settings: Codable, Equatable {
        var moneyGoal: Double
        var learnedCategories: [String: String]
    }

    var format = SnapceiptBackup.formatName
    var version = 1
    var exportedAt: Date
    var receipts: [Entry]
    var settings: Settings?
}

/// Exporting a backup or a spreadsheet, and importing either, from Settings → Your data.
enum DataTransfer {
    struct ImportResult: Equatable {
        var added = 0
        var skipped = 0
        var unreadable = 0

        var summary: String {
            var parts = ["\(added) added"]
            if skipped > 0 { parts.append("\(skipped) already here, skipped") }
            if unreadable > 0 { parts.append("\(unreadable) row\(unreadable == 1 ? "" : "s") couldn’t be read") }
            return parts.joined(separator: " · ")
        }
    }

    enum ImportError: LocalizedError {
        case unknownFormat, newerVersion

        var errorDescription: String? {
            switch self {
            case .unknownFormat: "That file isn’t a Snapceipt backup or a CSV with date and amount columns."
            case .newerVersion: "This backup was made by a newer Snapceipt. Update the app, then import it."
            }
        }
    }

    // MARK: Export

    static func backup(of receipts: [Receipt], includePhotos: Bool, defaults: UserDefaults = .standard, now: Date = .now) -> SnapceiptBackup {
        SnapceiptBackup(
            exportedAt: now,
            receipts: receipts.sorted { $0.date < $1.date }.map { receipt in
                SnapceiptBackup.Entry(
                    shop: receipt.shopName, date: receipt.date, total: receipt.total, vat: receipt.vat,
                    kind: receipt.kindRaw, isFullTaxInvoice: receipt.isFullTaxInvoice, sellerTaxID: receipt.sellerTaxID,
                    billUnits: receipt.billUnits, reader: receipt.reader, rawText: receipt.rawText,
                    isIncome: receipt.isIncome, incomeSource: receipt.incomeSourceRaw,
                    items: receipt.sortedItems.map { .init(name: $0.name, quantity: $0.quantity, total: $0.total, category: $0.categoryRaw) },
                    photo: includePhotos ? receipt.imageData : nil
                )
            },
            settings: .init(
                moneyGoal: defaults.double(forKey: "moneyGoal"),
                learnedCategories: defaults.dictionary(forKey: "learnedCategories") as? [String: String] ?? [:]
            )
        )
    }

    static func encode(_ backup: SnapceiptBackup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(backup)
    }

    static let csvHeader = ["Date", "Time", "Shop", "In or out", "Category", "Items", "Total", "VAT", "Full tax invoice", "Type", "Read by"]

    /// One row per receipt or income, for Excel, Numbers or Google Sheets. Money out is negative
    /// in "Total" so a column sum is the net; "In or out" says it in words too.
    static func csv(of receipts: [Receipt]) -> String {
        let day = DateFormatter.fixed("yyyy-MM-dd")
        let time = DateFormatter.fixed("HH:mm")
        var lines = [csvHeader.map(csvField).joined(separator: ",")]
        for receipt in receipts.sorted(by: { $0.date < $1.date }) {
            let category = receipt.isIncome ? receipt.incomeSource.name : receipt.kind.isBill ? SpendCategory.utilities.name : receipt.mainCategory.name
            let items = receipt.sortedItems.map { "\($0.name) \(String(format: "%.2f", $0.total))" }.joined(separator: "; ")
            let total = receipt.isIncome ? receipt.total : -receipt.total
            let row = [
                day.string(from: receipt.date), time.string(from: receipt.date), receipt.shopName,
                receipt.isIncome ? "in" : "out", category, items,
                String(format: "%.2f", total), String(format: "%.2f", receipt.vat),
                receipt.isFullTaxInvoice ? "yes" : "no", receipt.isIncome ? "Income" : receipt.kind.name, receipt.reader,
            ]
            lines.append(row.map(csvField).joined(separator: ","))
        }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    private static func csvField(_ text: String) -> String {
        text.contains(where: { ",\"\n\r".contains($0) }) ? "\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : text
    }

    // MARK: Import

    /// A Snapceipt backup (JSON) or a CSV, added to what's already here. Anything that matches a
    /// saved receipt (same shop and total, within 10 minutes) is skipped, so importing twice is safe.
    @discardableResult
    static func importFile(_ data: Data, into context: ModelContext, defaults: UserDefaults = .standard) throws -> ImportResult {
        let trimmed = data.prefix(64).drop { [0x20, 0x0A, 0x0D, 0x09, 0xEF, 0xBB, 0xBF].contains($0) }
        if trimmed.first == UInt8(ascii: "{") {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            guard let backup = try? decoder.decode(SnapceiptBackup.self, from: data), backup.format == SnapceiptBackup.formatName else {
                throw ImportError.unknownFormat
            }
            guard backup.version <= 1 else { throw ImportError.newerVersion }
            return importBackup(backup, into: context, defaults: defaults)
        }
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .windowsCP874) else {
            throw ImportError.unknownFormat
        }
        return try importCSV(text, into: context)
    }

    static func importBackup(_ backup: SnapceiptBackup, into context: ModelContext, defaults: UserDefaults = .standard) -> ImportResult {
        var result = ImportResult()
        var saved = existing(in: context)
        for entry in backup.receipts {
            if DuplicateCheck.firstMatch(shop: entry.shop, total: entry.total, date: entry.date, among: saved) != nil {
                result.skipped += 1
                continue
            }
            let receipt = Receipt(
                shopName: entry.shop, date: entry.date, total: entry.total, vat: entry.vat,
                kind: ReceiptKind(rawValue: entry.kind) ?? .purchase, isFullTaxInvoice: entry.isFullTaxInvoice,
                sellerTaxID: entry.sellerTaxID, billUnits: entry.billUnits, reader: entry.reader,
                rawText: entry.rawText, imageData: entry.photo
            )
            receipt.isIncome = entry.isIncome
            receipt.incomeSourceRaw = entry.incomeSource
            context.insert(receipt)
            for (index, item) in entry.items.enumerated() {
                let line = LineItem(name: item.name, quantity: item.quantity, total: item.total,
                                    category: SpendCategory(rawValue: item.category) ?? .other, position: index)
                context.insert(line)
                line.receipt = receipt
            }
            saved.append(receipt.duplicateCandidate)
            result.added += 1
        }
        if let settings = backup.settings {
            // The goal comes across only if none is set here; corrections are merged, this device's first.
            if defaults.double(forKey: "moneyGoal") == 0, settings.moneyGoal > 0 { defaults.set(settings.moneyGoal, forKey: "moneyGoal") }
            if !settings.learnedCategories.isEmpty {
                let mine = defaults.dictionary(forKey: "learnedCategories") as? [String: String] ?? [:]
                defaults.set(settings.learnedCategories.merging(mine) { _, here in here }, forKey: "learnedCategories")
            }
        }
        try? context.save()
        return result
    }

    /// A spreadsheet from Snapceipt, a bank or another app. It needs a date column and an amount
    /// column; shop (or description), category, items, VAT and in/out are used when there.
    /// Without an in/out column, negative amounts are money out and positive ones money in, as
    /// banks write them, unless nothing is negative, when everything is money out.
    static func importCSV(_ text: String, into context: ModelContext) throws -> ImportResult {
        let rows = parseCSV(text).filter { $0.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        guard let header = rows.first else { throw ImportError.unknownFormat }
        let names = header.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        func column(_ options: [String]) -> Int? {
            options.lazy.compactMap { option in names.firstIndex { $0 == option } }.first
                ?? options.lazy.compactMap { option in names.firstIndex { $0.contains(option) } }.first
        }
        guard let dateColumn = column(["date", "วันที่"]),
              let amountColumn = column(["total", "amount", "จำนวนเงิน", "ยอด"]) else { throw ImportError.unknownFormat }
        let timeColumn = column(["time", "เวลา"])
        let shopColumn = column(["shop", "merchant", "payee", "description", "name", "รายการ", "ร้าน"])
        let categoryColumn = column(["category", "หมวด"])
        let itemsColumn = column(["items"])
        let vatColumn = column(["vat"])
        let flowColumn = column(["in or out", "in/out", "type", "ประเภท"])
        let invoiceColumn = column(["full tax invoice"])

        let body = rows.dropFirst()
        let anyNegative = body.contains { (number($0[safe: amountColumn]) ?? 0) < 0 }
        var result = ImportResult()
        var saved = existing(in: context)
        for row in body {
            guard let rawAmount = number(row[safe: amountColumn]), rawAmount != 0,
                  let date = parseDate(row[safe: dateColumn], time: timeColumn.map { row[safe: $0] }) else {
                result.unreadable += 1
                continue
            }
            let flowWord = flowColumn.map { row[safe: $0].trimmingCharacters(in: .whitespaces).lowercased() } ?? ""
            let isIncome: Bool
            if ["in", "income", "money in", "รายรับ", "credit", "deposit"].contains(flowWord) {
                isIncome = true
            } else if ["out", "expense", "money out", "รายจ่าย", "debit", "withdrawal",
                        "purchase", "electricity", "water", "internet & phone"].contains(flowWord) {
                isIncome = false
            } else {
                isIncome = anyNegative && rawAmount > 0
            }
            let amount = abs(rawAmount)
            let shop = shopColumn.map { row[safe: $0].trimmingCharacters(in: .whitespaces) }.flatMap { $0.isEmpty ? nil : $0 } ?? (isIncome ? "Income" : "Imported")
            if DuplicateCheck.firstMatch(shop: shop, total: amount, date: date, among: saved) != nil {
                result.skipped += 1
                continue
            }
            let receipt = Receipt(shopName: shop, date: date, total: amount,
                                  vat: vatColumn.flatMap { number(row[safe: $0]) }.map(abs) ?? 0,
                                  kind: .purchase,
                                  isFullTaxInvoice: invoiceColumn.map { ["yes", "true", "1"].contains(row[safe: $0].lowercased()) } ?? false,
                                  reader: "Imported", rawText: "")
            receipt.isIncome = isIncome
            context.insert(receipt)
            if isIncome {
                receipt.incomeSource = QuickEntryRules.incomeSource(in: shop) ?? .other
            } else {
                let named = categoryColumn.map { row[safe: $0] } ?? ""
                let category = spendCategory(named) ?? QuickEntryRules.category(for: shop, aiGuess: nil)
                let items = itemsColumn.map { parseItems(row[safe: $0]) } ?? []
                let lines = items.isEmpty ? [(shop, amount)] : items
                for (index, item) in lines.enumerated() {
                    let line = LineItem(name: item.0, total: item.1, category: category, position: index)
                    context.insert(line)
                    line.receipt = receipt
                }
            }
            saved.append(receipt.duplicateCandidate)
            result.added += 1
        }
        try? context.save()
        return result
    }

    // MARK: Helpers

    private static func existing(in context: ModelContext) -> [DuplicateCheck.Candidate] {
        ((try? context.fetch(FetchDescriptor<Receipt>())) ?? []).map(\.duplicateCandidate)
    }

    static func spendCategory(_ text: String) -> SpendCategory? {
        let key = text.trimmingCharacters(in: .whitespaces).lowercased()
        guard !key.isEmpty else { return nil }
        return SpendCategory.allCases.first { $0.rawValue == key || $0.name.lowercased() == key || $0.thaiName == key }
    }

    /// "coffee 45.00; cake 80.00" back into items.
    static func parseItems(_ text: String) -> [(String, Double)] {
        text.split(separator: ";").compactMap { part in
            let piece = part.trimmingCharacters(in: .whitespaces)
            guard let space = piece.lastIndex(of: " "), let value = Double(piece[piece.index(after: space)...]) else { return nil }
            return (String(piece[..<space]), value)
        }
    }

    /// "1,290.00", "-฿60", "(250.00)" and "฿ 45" all read as numbers.
    static func number(_ text: String) -> Double? {
        var clean = text.trimmingCharacters(in: .whitespaces)
        var negative = false
        if clean.hasPrefix("(") && clean.hasSuffix(")") { negative = true; clean = String(clean.dropFirst().dropLast()) }
        clean = clean.replacingOccurrences(of: #"[฿,\s]|THB|บาท"#, with: "", options: .regularExpression)
        if clean.hasPrefix("−") { clean = "-" + clean.dropFirst() }
        guard let value = Double(clean) else { return nil }
        return negative ? -abs(value) : value
    }

    /// ISO dates, day/month/year (Thai style, Buddhist years too) and an optional time.
    static func parseDate(_ text: String, time: String?) -> Date? {
        let raw = text.trimmingCharacters(in: .whitespaces)
        let full = [raw, time?.trimmingCharacters(in: .whitespaces) ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd'T'HH:mm:ssXXXXX", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd",
                       "d/M/yyyy HH:mm", "d/M/yyyy H:mm", "d/M/yyyy", "d-M-yyyy", "d.M.yyyy"] {
            if let date = DateFormatter.fixed(format).date(from: full) ?? DateFormatter.fixed(format).date(from: raw) {
                // Buddhist-era years (2569) are 543 ahead of the Gregorian ones.
                let year = Calendar.app.component(.year, from: date)
                return year > 2400 ? Calendar.app.date(byAdding: .year, value: -543, to: date) : date
            }
        }
        return nil
    }

    /// Commas, quotes ("a, b"), doubled quotes and line breaks inside quotes, as spreadsheets write them.
    static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var chars = text.makeIterator()
        var pending: Character? = nil
        let delimiter: Character = text.prefix(2000).filter { $0 == ";" }.count > text.prefix(2000).filter { $0 == "," }.count ? ";" : ","
        while let c = pending ?? chars.next() {
            pending = nil
            if quoted {
                if c == "\"" {
                    if let next = chars.next() {
                        if next == "\"" { field.append("\"") } else { quoted = false; pending = next }
                    } else { quoted = false }
                } else {
                    field.append(c)
                }
            } else if c == "\"" {
                quoted = true
            } else if c == delimiter {
                row.append(field); field = ""
            } else if c == "\n" || c == "\r\n" || c == "\r" {
                row.append(field); field = ""
                rows.append(row); row = []
            } else if c != "\u{FEFF}" {
                field.append(c)
            }
        }
        if !field.isEmpty || !row.isEmpty { row.append(field); rows.append(row) }
        return rows
    }
}

extension Array where Element == String {
    subscript(safe index: Int) -> String { indices.contains(index) ? self[index] : "" }
}

extension DateFormatter {
    /// A Gregorian, POSIX formatter for files, whatever calendar the phone shows.
    static func fixed(_ format: String) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter
    }
}

extension String.Encoding {
    /// Thai Windows text, as older Thai bank exports use.
    static let windowsCP874 = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.dosThai.rawValue)))
}
