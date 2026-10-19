import Foundation

/// Spots a scan that's already been saved, so the same receipt isn't counted twice.
enum DuplicateCheck {
    struct Candidate {
        let shop: String
        let total: Double
        let date: Date
    }

    /// Index of the first saved receipt that looks like the same purchase: the same shop,
    /// the same total to the satang, and a time within 10 minutes. A scan with no printed
    /// time (00:00) matches anything from the same day.
    static func firstMatch(shop: String, total: Double, date: Date, among saved: [Candidate], calendar: Calendar = .app) -> Int? {
        let shopKey = MerchantCategorizer.normalize(shop)
        let midnight = calendar.startOfDay(for: date) == date
        return saved.firstIndex { other in
            guard MerchantCategorizer.normalize(other.shop) == shopKey, abs(other.total - total) <= 0.01 else { return false }
            if midnight || calendar.startOfDay(for: other.date) == other.date {
                return calendar.isDate(other.date, inSameDayAs: date)
            }
            return abs(other.date.timeIntervalSince(date)) <= 10 * 60
        }
    }

    /// The window of saved receipts worth checking against a scan dated `date`.
    static func searchWindow(around date: Date, calendar: Calendar = .app) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        return DateInterval(start: calendar.date(byAdding: .day, value: -1, to: day)!,
                            end: calendar.date(byAdding: .day, value: 2, to: day)!)
    }
}

/// What the Receipts search box matches: the shop, item names, the text read from the photo,
/// category names in English and Thai, and amounts ("129" finds ฿129.00).
enum ReceiptSearch {
    struct Fields {
        let shop: String
        let rawText: String
        let total: Double
        let categories: [SpendCategory]
        let items: [(name: String, total: Double)]
    }

    static func matches(_ query: String, _ fields: Fields) -> Bool {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return true }
        if fields.shop.localizedCaseInsensitiveContains(text)
            || fields.rawText.localizedCaseInsensitiveContains(text)
            || fields.items.contains(where: { $0.name.localizedCaseInsensitiveContains(text) })
            || fields.categories.contains(where: { $0.name.localizedCaseInsensitiveContains(text) || $0.thaiName.contains(text) }) {
            return true
        }
        guard let amount = amount(in: text) else { return false }
        let wholeBaht = !text.contains(".")
        func same(_ value: Double) -> Bool {
            wholeBaht ? abs(value.rounded(.towardZero) - amount) < 0.001 : abs(value - amount) < 0.005
        }
        return same(fields.total) || fields.items.contains { same($0.total) }
    }

    /// "฿1,600", "1600" or "129.50" as a number; nil for anything else.
    static func amount(in text: String) -> Double? {
        let cleaned = text.replacingOccurrences(of: "฿", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespaces)
        guard !cleaned.isEmpty, cleaned.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") }) else { return nil }
        return Double(cleaned)
    }
}

extension Receipt {
    var searchFields: ReceiptSearch.Fields {
        var categories = Set(items.map(\.category))
        categories.insert(mainCategory)
        return ReceiptSearch.Fields(
            shop: shopName,
            rawText: rawText,
            total: total,
            categories: Array(categories),
            items: items.map { ($0.name, $0.total) }
        )
    }

    var duplicateCandidate: DuplicateCheck.Candidate {
        DuplicateCheck.Candidate(shop: shopName, total: total, date: date)
    }
}
