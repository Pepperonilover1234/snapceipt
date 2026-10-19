import Foundation
import SwiftData

@Model
final class Receipt {
    var shopName: String = ""
    var date: Date = Date.now
    /// Amount paid in baht, VAT included.
    var total: Double = 0
    /// VAT included in `total` (7% in Thailand).
    var vat: Double = 0
    var kindRaw: String = ReceiptKind.purchase.rawValue
    /// ใบกำกับภาษีเต็มรูป: the only kind of receipt that counts for shopping tax deductions.
    var isFullTaxInvoice: Bool = false
    var sellerTaxID: String = ""
    /// kWh for electricity, m³ for water.
    var billUnits: Double = 0
    /// How the receipt was read: "Apple Intelligence", "Text rules" or "Sample".
    var reader: String = ""
    var rawText: String = ""
    @Attribute(.externalStorage) var imageData: Data?
    /// Money in (salary, a sale, a refund) rather than money spent. Income never counts as spending.
    var isIncome: Bool = false
    /// Where income came from; empty for spending.
    var incomeSourceRaw: String = ""
    @Relationship(deleteRule: .cascade, inverse: \LineItem.receipt) var items: [LineItem] = []

    init(
        shopName: String,
        date: Date,
        total: Double,
        vat: Double,
        kind: ReceiptKind,
        isFullTaxInvoice: Bool,
        sellerTaxID: String = "",
        billUnits: Double = 0,
        reader: String,
        rawText: String = "",
        imageData: Data? = nil
    ) {
        self.shopName = shopName
        self.date = date
        self.total = total
        self.vat = vat
        self.kindRaw = kind.rawValue
        self.isFullTaxInvoice = isFullTaxInvoice
        self.sellerTaxID = sellerTaxID
        self.billUnits = billUnits
        self.reader = reader
        self.rawText = rawText
        self.imageData = imageData
    }

    var kind: ReceiptKind {
        get { ReceiptKind(rawValue: kindRaw) ?? .purchase }
        set { kindRaw = newValue.rawValue }
    }

    var incomeSource: IncomeSource {
        get { IncomeSource(rawValue: incomeSourceRaw) ?? .other }
        set { incomeSourceRaw = newValue.rawValue }
    }

    var sortedItems: [LineItem] { items.sorted { $0.position < $1.position } }

    var itemsTotal: Double { items.reduce(0) { $0 + $1.total } }

    /// The category most of the money went to.
    var mainCategory: SpendCategory {
        if kind.isBill { return .utilities }
        var totals: [SpendCategory: Double] = [:]
        for item in items { totals[item.category, default: 0] += item.total }
        return totals.max { $0.value < $1.value }?.key ?? .other
    }
}

@Model
final class LineItem {
    var name: String = ""
    var quantity: Double = 1
    /// Line total in baht.
    var total: Double = 0
    var categoryRaw: String = SpendCategory.other.rawValue
    var position: Int = 0
    var receipt: Receipt?

    init(name: String, quantity: Double = 1, total: Double, category: SpendCategory, position: Int) {
        self.name = name
        self.quantity = quantity
        self.total = total
        self.categoryRaw = category.rawValue
        self.position = position
    }

    var category: SpendCategory {
        get { SpendCategory(rawValue: categoryRaw) ?? .other }
        set { categoryRaw = newValue.rawValue }
    }

    var unitPrice: Double { quantity > 0 ? total / quantity : total }
}

extension Receipt {
    /// Saves a reviewed scan, with its items, into the store.
    @discardableResult
    static func insert(_ draft: ParsedReceipt, into context: ModelContext) -> Receipt {
        let receipt = Receipt(
            shopName: draft.shopName.isEmpty ? "Receipt" : draft.shopName,
            date: draft.date,
            total: draft.total,
            vat: draft.vat,
            kind: draft.kind,
            isFullTaxInvoice: draft.isFullTaxInvoice,
            sellerTaxID: draft.sellerTaxID,
            billUnits: draft.billUnits,
            reader: draft.reader.rawValue,
            rawText: draft.rawText,
            imageData: draft.imageData
        )
        context.insert(receipt)
        for (index, item) in draft.items.enumerated() where !item.name.isEmpty || item.total != 0 {
            let line = LineItem(
                name: item.name.isEmpty ? "Item" : item.name,
                quantity: item.quantity,
                total: item.total,
                category: item.category,
                position: index
            )
            context.insert(line)
            line.receipt = receipt
        }
        return receipt
    }
}
