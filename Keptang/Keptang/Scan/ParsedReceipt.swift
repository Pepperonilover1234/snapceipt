import Foundation

/// A receipt read from a photo, before the person reviews and saves it.
struct ParsedReceipt {
    enum Reader: String {
        case appleIntelligence = "Apple Intelligence"
        case textRules = "Text rules"
    }

    var shopName = ""
    var date = Date.now
    var items: [ParsedItem] = []
    var total: Double = 0
    var vat: Double = 0
    var kind: ReceiptKind = .purchase
    var isFullTaxInvoice = false
    var sellerTaxID = ""
    var billUnits: Double = 0
    var reader: Reader = .textRules
    var rawText = ""
    var imageData: Data?
    /// True when a total line (ยอดสุทธิ, TOTAL…) was found in the printed text.
    var foundPrintedTotal = false
    /// True when a date was found in the printed text.
    var foundPrintedDate = false

    var itemsTotal: Double { items.reduce(0) { $0 + $1.total } }
}

struct ParsedItem: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var quantity: Double = 1
    var total: Double
    var category: SpendCategory = .other
    /// The category the app picked, so a change by the person can be learned.
    var suggestedCategory: SpendCategory = .other
    /// The category Apple Intelligence picked, if it read this receipt.
    var aiCategory: SpendCategory?

    var unitPrice: Double { quantity > 0 ? total / quantity : total }
}

extension ParsedReceipt {
    /// What was read, for checking scans in the console.
    var debugSummary: String {
        var lines = [
            "── Snapceipt scan (\(reader.rawValue)) ──",
            "Shop: \(shopName)",
            "Date: \(date.formatted(date: .abbreviated, time: .shortened)) (printed: \(foundPrintedDate))",
            "Kind: \(kind.name)  Full tax invoice: \(isFullTaxInvoice)  Seller tax ID: \(sellerTaxID.isEmpty ? "-" : sellerTaxID)",
        ]
        for item in items {
            lines.append("  • \(item.name)  ×\(item.quantity.formatted())  \(item.total.baht)  [\(item.category.name)]")
        }
        lines.append("Items sum: \(itemsTotal.baht)  Total: \(total.baht) (printed: \(foundPrintedTotal))  VAT: \(vat.baht)  Units: \(billUnits.formatted())")
        lines.append("── Text read ──")
        lines.append(rawText)
        return lines.joined(separator: "\n")
    }
}
