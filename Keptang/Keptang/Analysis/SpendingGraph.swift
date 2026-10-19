import Foundation

/// One receipt as the graph sees it: a plain copy, so the graph is pure and testable.
struct GraphReceipt: Hashable {
    /// Stable across launches (the receipt's encoded persistent id); any unique string in tests.
    let key: String
    let shop: String
    let date: Date
    let total: Double
    let kind: ReceiptKind
    /// Money per category, adding up to `total`, as the totals use it.
    let categories: [SpendCategory: Double]
    /// Item names, without VAT, discount and rounding lines.
    let items: [String]
    let hasPhoto: Bool
    let rawText: String

    var mainCategory: SpendCategory { categories.max { $0.value < $1.value }?.key ?? .other }
}

/// Snapceipt's take on Obsidian's graph view, with receipts playing the part of notes.
///
/// | Obsidian            | Here                                                        |
/// |---------------------|-------------------------------------------------------------|
/// | note                | receipt                                                     |
/// | link to a note      | receipt → its shop (shops are the hubs), receipt → its items |
/// | tag                 | category                                                    |
/// | attachment          | the receipt's photo                                         |
/// | unresolved link     | a shop that couldn't be read ("Unknown shop")               |
/// | orphan              | a receipt that shares no shop or item with another          |
///
/// A receipt that `DuplicateCheck` would flag as already saved adds no node or edge.
struct SpendingGraph {
    struct Node: Identifiable, Hashable {
        enum Kind: String { case receipt, shop, category, item, photo, unknownShop }

        let id: String
        let kind: Kind
        let title: String
        var receiptKey: String?
        var category: SpendCategory?
        /// Receipts linked to this node (1 for a receipt).
        var count = 0
        /// Money spent through this node: a receipt's total, a shop's or item's sum, a category's share.
        var amount = 0.0
        var firstDate: Date?
        var lastDate: Date?
    }

    struct Edge: Hashable {
        enum Kind: Hashable { case link, suggested, confirmed }
        let from: String
        let to: String
        var kind: Kind = .link
        var score = 1.0
        var reason = ""
    }

    private(set) var nodes: [Node] = []
    private(set) var edges: [Edge] = []
    /// Keys of receipts left out as duplicates.
    private(set) var duplicates: Set<String> = []
    private(set) var receipts: [String: GraphReceipt] = [:]
    private var index: [String: Int] = [:]

    func node(_ id: String) -> Node? { index[id].map { nodes[$0] } }

    static func receiptID(_ key: String) -> String { "r:" + key }
    static let unknownShopID = "s:?"

    /// Receipts linked to a hub (shop, item, category, photo), newest first: Obsidian's backlinks.
    func backlinks(of id: String) -> [GraphReceipt] {
        edges.filter { $0.to == id && $0.kind == .link }
            .compactMap { node($0.from)?.receiptKey.flatMap { receipts[$0] } }
            .sorted { $0.date > $1.date }
    }

    func neighbours(of id: String) -> Set<String> {
        Set(edges.compactMap { $0.from == id ? $0.to : $0.to == id ? $0.from : nil })
    }

    /// Whether the shop name tells us nothing: empty, the scanner's fallback, or just the bill's type.
    static func isUnknownShop(_ shop: String, kind: ReceiptKind) -> Bool {
        let name = shop.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name == "Receipt" || name.caseInsensitiveCompare(kind.name) == .orderedSame
    }

    /// The same duplicate rule as saving a scan: same shop, same total, within 10 minutes. Later copies go.
    static func duplicates(in receipts: [GraphReceipt], calendar: Calendar = .app) -> Set<String> {
        var dropped = Set<String>()
        let byShop = Dictionary(grouping: receipts.sorted { ($0.date, $0.key) < ($1.date, $1.key) }) { MerchantCategorizer.normalize($0.shop) }
        for group in byShop.values {
            var kept: [GraphReceipt] = []
            for receipt in group {
                let candidates = kept.map { DuplicateCheck.Candidate(shop: $0.shop, total: $0.total, date: $0.date) }
                if DuplicateCheck.firstMatch(shop: receipt.shop, total: receipt.total, date: receipt.date, among: candidates, calendar: calendar) != nil {
                    dropped.insert(receipt.key)
                } else {
                    kept.append(receipt)
                }
            }
        }
        return dropped
    }

    init(receipts all: [GraphReceipt], calendar: Calendar = .app) {
        duplicates = Self.duplicates(in: all, calendar: calendar)
        for receipt in all where !duplicates.contains(receipt.key) {
            receipts[receipt.key] = receipt
            let rid = Self.receiptID(receipt.key)
            let shopName = receipt.shop.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = "\(Self.isUnknownShop(shopName, kind: receipt.kind) ? "Receipt" : shopName) · \(receipt.date.formatted(.dateTime.day().month(.abbreviated)))"
            add(Node(id: rid, kind: .receipt, title: title, receiptKey: receipt.key, category: receipt.mainCategory,
                     count: 1, amount: receipt.total, firstDate: receipt.date, lastDate: receipt.date))

            if Self.isUnknownShop(shopName, kind: receipt.kind) {
                link(rid, hub: Self.unknownShopID, kind: .unknownShop, title: "Unknown shop", receipt: receipt, amount: receipt.total)
            } else {
                link(rid, hub: "s:" + MerchantCategorizer.normalize(shopName), kind: .shop, title: shopName, receipt: receipt, amount: receipt.total)
            }
            for (category, amount) in receipt.categories where amount > 0.005 {
                link(rid, hub: "c:" + category.rawValue, kind: .category, title: category.name, receipt: receipt, amount: amount, category: category)
            }
            var seenItems = Set<String>()
            for item in receipt.items {
                let key = CategoryLearner.normalize(item)
                guard !key.isEmpty, seenItems.insert(key).inserted else { continue }
                link(rid, hub: "i:" + key, kind: .item, title: item, receipt: receipt, amount: 0)
            }
            if receipt.hasPhoto {
                link(rid, hub: "p:" + receipt.key, kind: .photo, title: "Photo", receipt: receipt, amount: 0)
            }
        }
    }

    private init(nodes: [Node], edges: [Edge], receipts: [String: GraphReceipt], duplicates: Set<String>) {
        self.nodes = nodes
        self.edges = edges
        self.receipts = receipts
        self.duplicates = duplicates
        for (i, node) in nodes.enumerated() { index[node.id] = i }
    }

    private mutating func add(_ node: Node) {
        index[node.id] = nodes.count
        nodes.append(node)
    }

    private mutating func link(_ receipt: String, hub: String, kind: Node.Kind, title: String, receipt source: GraphReceipt,
                               amount: Double, category: SpendCategory? = nil) {
        if let i = index[hub] {
            nodes[i].count += 1
            nodes[i].amount += amount
            nodes[i].firstDate = min(nodes[i].firstDate ?? source.date, source.date)
            nodes[i].lastDate = max(nodes[i].lastDate ?? source.date, source.date)
        } else {
            add(Node(id: hub, kind: kind, title: title, category: category, count: 1, amount: amount, firstDate: source.date, lastDate: source.date))
        }
        edges.append(Edge(from: receipt, to: hub))
    }

    // MARK: - Filtering

    enum DateRange: String, CaseIterable, Codable {
        case month = "1M", year = "1Y", all = "All"

        func contains(_ date: Date, now: Date) -> Bool {
            switch self {
            case .month: TimeRange.month.interval(endingAt: now).contains(date)
            case .year: TimeRange.year.interval(endingAt: now).contains(date)
            case .all: true
            }
        }
    }

    /// What to show. Filters only change the view, never the receipts.
    struct Filter: Codable, Equatable {
        var search = ""
        var range: DateRange = .month
        var category: SpendCategory?
        var showReceipts = true
        var showItems = false
        /// Category nodes, Obsidian's "Tags".
        var showCategories = false
        /// Receipt photos, Obsidian's "Attachments".
        var showPhotos = false
        /// Hides the Unknown shop node, Obsidian's "Existing files only".
        var existingOnly = false
        var showOrphans = true
        var showSuggestions = true
        var minimumScore = LinkSuggester.defaultThreshold
    }

    struct Local: Equatable {
        var center: String
        var depth = 1
        var incoming = true
        var outgoing = true
        var neighbourLinks = false
    }

    /// The graph as shown. `suggestions` are ML links between receipts; `decisions` are the person's
    /// confirmations (true) and dismissals (false), keyed by `LinkSuggester.pairKey`.
    func filtered(_ filter: Filter, local: Local? = nil, suggestions: [LinkSuggester.Suggestion] = [],
                  decisions: [String: Bool] = [:], now: Date = .now) -> (graph: SpendingGraph, distance: [String: Int]) {
        let query = GraphQuery(filter.search)
        let visibleReceipts = Set(receipts.values.filter { receipt in
            filter.range.contains(receipt.date, now: now)
                && (filter.category.map { receipt.categories[$0, default: 0] > 0 } ?? true)
                && (query.isEmpty || query.matches(receipt))
        }.map { Self.receiptID($0.key) })

        var keep = visibleReceipts
        var kept: [Edge] = []
        for edge in edges where visibleReceipts.contains(edge.from) {
            guard let hub = node(edge.to) else { continue }
            let allowed = switch hub.kind {
            case .shop: true
            case .unknownShop: !filter.existingOnly
            case .category: filter.showCategories
            case .item: filter.showItems
            case .photo: filter.showPhotos
            case .receipt: false
            }
            if allowed {
                keep.insert(hub.id)
                kept.append(edge)
            }
        }

        // ML links: confirmed ones always (unless a side is hidden), suggestions above the threshold.
        var extra: [Edge] = []
        for suggestion in suggestions {
            let a = Self.receiptID(suggestion.a), b = Self.receiptID(suggestion.b)
            guard visibleReceipts.contains(a), visibleReceipts.contains(b) else { continue }
            switch decisions[suggestion.pairKey] {
            case true?: extra.append(Edge(from: a, to: b, kind: .confirmed, score: suggestion.score, reason: suggestion.reason))
            case false?: continue
            case nil:
                if filter.showSuggestions, suggestion.score >= filter.minimumScore {
                    extra.append(Edge(from: a, to: b, kind: .suggested, score: suggestion.score, reason: suggestion.reason))
                }
            }
        }

        if !filter.showOrphans {
            // A receipt is an orphan when no other shown receipt shares its shop or an item.
            var shared: [String: Int] = [:]
            for edge in edges where visibleReceipts.contains(edge.from) {
                if let kind = node(edge.to)?.kind, kind == .shop || kind == .item { shared[edge.to, default: 0] += 1 }
            }
            let connected = Set(edges.filter { visibleReceipts.contains($0.from) && (shared[$0.to] ?? 0) > 1 }.map(\.from))
                .union(extra.filter { $0.kind == .confirmed }.flatMap { [$0.from, $0.to] })
            let orphans = visibleReceipts.subtracting(connected)
            keep.subtract(orphans)
            kept.removeAll { orphans.contains($0.from) }
            extra.removeAll { orphans.contains($0.from) || orphans.contains($0.to) }
            let linked = Set(kept.map(\.to))
            keep = keep.filter { node($0)?.kind == .receipt || linked.contains($0) }
        }

        if !filter.showReceipts {
            // Hubs only: each shop links to the categories and items its receipts had.
            var hubEdges = Set<Edge>()
            let byReceipt = Dictionary(grouping: kept, by: \.from)
            for (_, links) in byReceipt {
                let shops = links.filter { [.shop, .unknownShop].contains(node($0.to)?.kind) }.map(\.to)
                let others = links.filter { ![.shop, .unknownShop].contains(node($0.to)?.kind) }.map(\.to)
                for shop in shops { for other in others { hubEdges.insert(Edge(from: shop, to: other)) } }
            }
            keep.subtract(visibleReceipts)
            kept = Array(hubEdges)
            extra = []
        }

        var all = kept + extra
        var distance: [String: Int] = [:]
        if let local, node(local.center) != nil {
            keep.insert(local.center)
            distance[local.center] = 0
            var frontier = [local.center]
            for level in 1...max(1, local.depth) {
                var next: [String] = []
                for id in frontier {
                    for edge in all {
                        // Suggested and confirmed links between receipts go both ways.
                        let twoWay = edge.kind != .link
                        let other = edge.from == id ? edge.to : edge.to == id ? edge.from : nil
                        guard let other, keep.contains(other), distance[other] == nil else { continue }
                        let forward = edge.from == id, backward = edge.to == id
                        if twoWay || (local.outgoing && forward) || (local.incoming && backward) {
                            distance[other] = level
                            next.append(other)
                        }
                    }
                }
                frontier = next
            }
            keep = Set(distance.keys)
            all = all.filter { keep.contains($0.from) && keep.contains($0.to) }
            if !local.neighbourLinks {
                all = all.filter { abs((distance[$0.from] ?? 0) - (distance[$0.to] ?? 0)) == 1 }
            }
        }
        all = all.filter { keep.contains($0.from) && keep.contains($0.to) }

        // Counts and amounts for what's shown, so a hub's size matches the filtered view.
        var shownNodes = nodes.filter { keep.contains($0.id) }
        let receiptCounts = Dictionary(grouping: all.filter { $0.kind == .link }, by: \.to)
        for i in shownNodes.indices where shownNodes[i].kind != .receipt {
            let links = receiptCounts[shownNodes[i].id] ?? []
            let shownReceipts = links.compactMap { node($0.from)?.receiptKey.flatMap { receipts[$0] } }
            if !shownReceipts.isEmpty {
                shownNodes[i].count = shownReceipts.count
                shownNodes[i].amount = shownNodes[i].category.map { c in shownReceipts.reduce(0) { $0 + $1.categories[c, default: 0] } }
                    ?? shownReceipts.reduce(0) { $0 + $1.total }
            }
        }
        return (SpendingGraph(nodes: shownNodes, edges: all, receipts: receipts, duplicates: duplicates), distance)
    }
}

/// Obsidian-style search for the spending graph. Words match the shop, items, categories (English or
/// Thai), the text read from the photo, an amount ("129") or a date ("17 Oct", "2026-10-17").
/// `shop:`, `item:`, `category:` (or `tag:`) and `main:` (the main category) narrow a word; `-word` leaves it out. Every part must match.
struct GraphQuery {
    struct Term {
        enum Field { case any, shop, item, category, main }
        var field: Field
        var value: String
        var negated: Bool
    }

    let terms: [Term]
    var isEmpty: Bool { terms.isEmpty }

    init(_ text: String) {
        var terms: [Term] = []
        for match in text.matches(of: /(-?)(?:(shop|item|category|tag|main):)?(?:"([^"]*)"|(\S+))/) {
            let value = String(match.output.3 ?? match.output.4 ?? "").lowercased()
            guard !value.isEmpty else { continue }
            let field: Term.Field = switch match.output.2.map(String.init) {
            case "shop": .shop
            case "item": .item
            case "category", "tag": .category
            case "main": .main
            default: .any
            }
            terms.append(Term(field: field, value: value, negated: !match.output.1.isEmpty))
        }
        self.terms = terms
    }

    func matches(_ receipt: GraphReceipt) -> Bool {
        terms.allSatisfy { term in
            let value = term.value
            let categoryHit = receipt.categories.keys.contains {
                $0.rawValue == value || $0.name.lowercased().contains(value) || $0.thaiName.contains(value)
            }
            let hit: Bool = switch term.field {
            case .shop: receipt.shop.lowercased().contains(value)
            case .item: receipt.items.contains { $0.lowercased().contains(value) }
            case .category: categoryHit
            case .main: receipt.mainCategory.rawValue == value || receipt.mainCategory.name.lowercased() == value
            case .any:
                ReceiptSearch.matches(value, ReceiptSearch.Fields(
                    shop: receipt.shop, rawText: receipt.rawText, total: receipt.total,
                    categories: Array(receipt.categories.keys), items: receipt.items.map { ($0, 0) }))
                    || Self.dateStrings(receipt.date).contains { $0.contains(value) }
            }
            return hit != term.negated
        }
    }

    private static func dateStrings(_ date: Date) -> [String] {
        [
            date.formatted(.dateTime.day().month(.abbreviated)).lowercased(),
            date.formatted(.dateTime.day().month(.wide).year()).lowercased(),
            date.formatted(.iso8601.year().month().day()),
            date.formatted(.dateTime.weekday(.wide)).lowercased(),
        ]
    }
}

extension SpendingGraph {
    /// Everything the graph search finds, best first: shops, categories and items whose names
    /// contain every typed word, then receipts the query matches (shop, item, category, amount,
    /// date, or `shop:` style terms), newest first. Photos aren't searched.
    func search(_ text: String) -> [Node] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let query = GraphQuery(trimmed)
        let words = trimmed.lowercased().split(separator: " ")
            .filter { !$0.contains(":") && !$0.hasPrefix("-") }
            .map(String.init)
        let hubs = nodes.filter { node in
            guard node.kind != .receipt, node.kind != .photo, !words.isEmpty else { return false }
            let title = node.title.lowercased()
            let thai = node.category?.thaiName ?? ""
            return words.allSatisfy { title.contains($0) || thai.contains($0) }
        }
        .sorted { ($0.count, $0.amount) > ($1.count, $1.amount) }
        let receiptHits = nodes.filter { node in
            node.kind == .receipt && node.receiptKey.flatMap { receipts[$0] }.map(query.matches) == true
        }
        .sorted { ($0.lastDate ?? .distantPast) > ($1.lastDate ?? .distantPast) }
        return hubs + receiptHits
    }
}
