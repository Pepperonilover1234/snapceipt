import UIKit

/// The scan pipeline: straighten → read text → understand items → sort into categories.
enum ReceiptReader {
    enum Step: Int, CaseIterable {
        case straightening, reading, understanding, sorting

        var title: String {
            switch self {
            case .straightening: "Straightening the photo"
            case .reading: "Reading the text"
            case .understanding: "Understanding the items"
            case .sorting: "Sorting into categories"
            }
        }

        var detail: String {
            switch self {
            case .straightening: "Vision finds the paper's corners and flattens it"
            case .reading: "Vision text recognition, Thai and English"
            case .understanding: OnDeviceAI.isAvailable ? "Apple Intelligence on this device" : "Built-in text rules"
            case .sorting: CategoryLearner.shared.hasCreateMLModel ? "Create ML model plus what you've taught it" : "Learned from your corrections"
            }
        }
    }

    static func read(
        _ image: UIImage,
        alreadyStraight: Bool,
        progress: @escaping @MainActor (Step) -> Void
    ) async throws -> ParsedReceipt {
        await progress(.straightening)
        let photo = image.limited(toLongSide: 2400)
        let straight = alreadyStraight ? photo : await ReceiptStraightener.straighten(photo)

        await progress(.reading)
        let lines = try await ReceiptOCR.lines(in: straight)

        await progress(.understanding)
        let rules = ReceiptRules.parse(lines: lines)
        var receipt = rules
        if OnDeviceAI.isAvailable {
            do {
                let ai = try await ReceiptAI.read(lines: lines)
                receipt = merge(ai: ai, rules: rules)
            } catch {
                receipt = rules
            }
        }

        await progress(.sorting)
        finalize(&receipt)
        receipt.rawText = lines.joined(separator: "\n")
        receipt.imageData = straight.limited(toLongSide: 1600).jpegData(compressionQuality: 0.7)
        return receipt
    }

    /// The AI writes cleaner names and categories; printed numbers found by the rules are trusted over the AI's.
    static func merge(ai: ParsedReceipt, rules: ParsedReceipt) -> ParsedReceipt {
        var receipt = ai
        if receipt.shopName.isEmpty { receipt.shopName = rules.shopName }
        if rules.foundPrintedDate || !ai.foundPrintedDate { receipt.date = rules.date }
        if rules.foundPrintedTotal, abs(ai.total - rules.total) > 0.5 { receipt.total = rules.total }
        if receipt.total <= 0 { receipt.total = rules.total }
        if rules.vat > 0 { receipt.vat = rules.vat }
        if rules.kind.isBill { receipt.kind = rules.kind }
        let lower = rules.rawText.lowercased()
        let mentionsInvoice = lower.contains("ใบกำกับภาษี") || lower.contains("tax invoice")
        receipt.isFullTaxInvoice = rules.isFullTaxInvoice || (ai.isFullTaxInvoice && mentionsInvoice && !lower.contains("อย่างย่อ"))
        receipt.sellerTaxID = rules.sellerTaxID
        receipt.billUnits = rules.billUnits
        receipt.foundPrintedTotal = rules.foundPrintedTotal

        // Keep whichever item list adds up closer to the total.
        let totalWords = ["total", "รวม", "ยอดสุทธิ", "vatable", "เงินทอน", "change", "cash", "เงินสด"]
        let aiItems = ai.items.filter { item in
            !totalWords.contains(where: item.name.lowercased().contains) || item.name.lowercased().hasPrefix("vat")
        }
        let aiGap = abs(aiItems.reduce(0) { $0 + $1.total } - receipt.total)
        let rulesGap = abs(rules.itemsTotal - receipt.total)
        if aiItems.isEmpty || (rulesGap + 0.5 < aiGap && !rules.items.isEmpty) {
            receipt.items = rules.items
        } else {
            receipt.items = aiItems
            let sum = aiItems.reduce(0) { $0 + $1.total }
            if receipt.vat > 0, abs(sum - receipt.total) >= 0.5, abs(sum + receipt.vat - receipt.total) < 0.5 {
                receipt.items.append(ParsedItem(name: "VAT 7%", total: receipt.vat))
            }
        }
        return receipt
    }

    /// Categories, VAT and rounding, the same for AI and rule results.
    static func finalize(_ receipt: inout ParsedReceipt) {
        for index in receipt.items.indices {
            var item = receipt.items[index]
            item.total = item.total.roundedToSatang()
            item.category = receipt.kind.isBill
                ? .utilities
                : MerchantCategorizer.category(forItem: item.name, shopName: receipt.shopName, aiGuess: item.aiCategory)
            receipt.items[index] = item
        }

        // VAT, service charge and discount lines belong to whatever the rest of the receipt was.
        var totals: [SpendCategory: Double] = [:]
        for item in receipt.items where !isAdjustment(item) { totals[item.category, default: 0] += item.total }
        let main = totals.max { $0.value < $1.value }?.key ?? .other
        for index in receipt.items.indices where isAdjustment(receipt.items[index]) {
            receipt.items[index].category = receipt.kind.isBill ? .utilities : main
        }
        for index in receipt.items.indices {
            receipt.items[index].suggestedCategory = receipt.items[index].category
        }

        receipt.total = receipt.total.roundedToSatang()
        if receipt.vat <= 0 {
            let lower = receipt.rawText.lowercased()
            let registeredForVAT = lower.contains("vat") || lower.contains("ภาษี") || lower.contains("tax invoice") || receipt.kind.isBill
            if registeredForVAT { receipt.vat = ThaiTax.vatIncluded(in: receipt.total) }
        }
        receipt.vat = receipt.vat.roundedToSatang()
        if receipt.shopName.isEmpty { receipt.shopName = receipt.kind.isBill ? receipt.kind.name : "Receipt" }
    }

    static func isAdjustment(_ item: ParsedItem) -> Bool {
        let lower = item.name.lowercased()
        return item.total < 0
            || lower.hasPrefix("vat") || lower.contains("ภาษีมูลค่าเพิ่ม") || lower.contains("service") || lower.contains("ค่าบริการ")
            || lower.contains("ส่วนลด") || lower.contains("discount") || lower.contains("ปัดเศษ") || lower.contains("rounding")
    }
}
