import Foundation
import FoundationModels

// Guided Generation: the on-device model fills these types directly, so the output is always valid Swift data.

@Generable
struct AIReceipt {
    @Guide(description: "Store, restaurant or company name printed at the top of the receipt. Keep Thai text exactly as printed.")
    var shopName: String

    @Guide(description: "Purchase or billing date as yyyy-MM-dd in the Gregorian calendar. Thai receipts often print Buddhist years: subtract 543 (2569 becomes 2026, and a two-digit 69 means 2026).")
    var date: String

    @Guide(description: "Every purchased product, dish or charge line. Skip total, subtotal, VAT, cash, change, card payment, member points and tax ID lines.")
    var items: [AIItem]

    @Guide(description: "Final amount paid in baht, including VAT and service charge, exactly as printed on the total line")
    var total: Double

    @Guide(description: "VAT amount in baht if printed on the receipt, otherwise 0")
    var vat: Double

    @Guide(description: "What kind of document this is")
    var kind: AIReceiptKind

    @Guide(description: "True only for a full tax invoice (ใบกำกับภาษีเต็มรูป or e-Tax invoice that shows the buyer's name). False for abbreviated tax invoices (อย่างย่อ, ABB) and plain receipts.")
    var isFullTaxInvoice: Bool
}

@Generable
struct AIItem {
    @Guide(description: "Clear, readable product name. Expand cut-off abbreviations (CP CHKN BRST becomes CP chicken breast). Keep Thai names in Thai and keep the brand.")
    var name: String

    @Guide(description: "Quantity bought, 1 if not shown. Can be a weight in kg.")
    var quantity: Double

    @Guide(description: "Line total in baht for this item. Negative for a discount line.")
    var price: Double

    @Guide(description: "What the item is")
    var category: AICategory
}

@Generable
enum AICategory {
    case groceries
    case foodAndDrinks
    case transport
    case shopping
    case healthAndBeauty
    case billsAndUtilities
    case entertainment
    case subscriptions
    case education
    case other

    var spendCategory: SpendCategory {
        switch self {
        case .groceries: .groceries
        case .foodAndDrinks: .dining
        case .transport: .transport
        case .shopping: .shopping
        case .healthAndBeauty: .health
        case .billsAndUtilities: .utilities
        case .entertainment: .entertainment
        case .subscriptions: .subscriptions
        case .education: .education
        case .other: .other
        }
    }
}

@Generable
enum AIReceiptKind {
    case purchase
    case electricityBill
    case waterBill
    case internetOrPhoneBill

    var receiptKind: ReceiptKind {
        switch self {
        case .purchase: .purchase
        case .electricityBill: .electricity
        case .waterBill: .water
        case .internetOrPhoneBill: .internet
        }
    }
}

enum ReceiptAI {
    static let instructions = """
        You read shop receipts and utility bills from Thailand and turn them into structured data. \
        The text comes from a photo, one printed row per line, in Thai and English. \
        Prices are in Thai baht. Only use numbers that are printed on the receipt; never invent items or prices.
        """

    static func prewarm() {
        guard OnDeviceAI.isAvailable else { return }
        LanguageModelSession(instructions: instructions).prewarm()
    }

    static func read(lines: [String]) async throws -> ParsedReceipt {
        let session = LanguageModelSession(instructions: instructions)
        let prompt = "Receipt text:\n\n" + lines.joined(separator: "\n")
        let response = try await session.respond(
            to: prompt,
            generating: AIReceipt.self,
            options: GenerationOptions(samplingMode: .greedy)
        )
        return response.content.parsedReceipt
    }
}

extension AIReceipt {
    var parsedReceipt: ParsedReceipt {
        var receipt = ParsedReceipt()
        receipt.reader = .appleIntelligence
        receipt.shopName = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        receipt.total = total
        receipt.vat = max(0, vat)
        receipt.kind = kind.receiptKind
        receipt.isFullTaxInvoice = isFullTaxInvoice
        if let parsed = Self.dateFormatter.date(from: date.trimmingCharacters(in: .whitespaces)) {
            receipt.date = Calendar.app.date(bySettingHour: 12, minute: 0, second: 0, of: parsed) ?? parsed
            receipt.foundPrintedDate = true
        }
        receipt.items = items.map { item in
            let category = item.category.spendCategory
            return ParsedItem(
                name: item.name.trimmingCharacters(in: .whitespacesAndNewlines),
                quantity: item.quantity > 0 ? item.quantity : 1,
                total: item.price,
                category: category,
                aiCategory: category
            )
        }
        return receipt
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
