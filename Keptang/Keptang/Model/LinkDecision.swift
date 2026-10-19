import Foundation
import SwiftData

/// What the person decided about a suggested link between two receipts: confirmed (drawn as a
/// solid link from now on) or dismissed (never suggested again). Added alongside the existing
/// models, so opening an older store is a lightweight migration that keeps every receipt.
@Model
final class LinkDecision {
    /// `LinkSuggester.pairKey` of the two receipts' graph keys.
    @Attribute(.unique) var pairKey: String = ""
    var confirmed: Bool = false
    var decidedAt: Date = Date.now

    init(pairKey: String, confirmed: Bool) {
        self.pairKey = pairKey
        self.confirmed = confirmed
    }

    /// Records or changes the decision for a pair.
    static func set(_ confirmed: Bool, for pairKey: String, in context: ModelContext) {
        let existing = try? context.fetch(FetchDescriptor<LinkDecision>(predicate: #Predicate { $0.pairKey == pairKey })).first
        if let existing {
            existing.confirmed = confirmed
            existing.decidedAt = .now
        } else {
            context.insert(LinkDecision(pairKey: pairKey, confirmed: confirmed))
        }
        try? context.save()
    }
}

extension Receipt {
    /// A key that survives relaunches: the receipt's persistent id, encoded with sorted keys so the
    /// same receipt always gives the same string.
    var graphKey: String {
        (try? Self.keyEncoder.encode(persistentModelID)).map { $0.base64EncodedString() } ?? shopName + date.description
    }

    private static let keyEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    func graphReceipt(key: String? = nil) -> GraphReceipt {
        let snapshot = ReceiptSnapshot(self)
        return GraphReceipt(
            key: key ?? graphKey,
            shop: shopName,
            date: date,
            total: total,
            kind: kind,
            categories: snapshot.categoryAmounts,
            items: sortedItems.filter { item in
                let probe = ParsedItem(name: item.name, total: item.total)
                return !ReceiptReader.isAdjustment(probe)
            }.map(\.name),
            hasPhoto: imageData != nil,
            rawText: rawText
        )
    }
}
