import Foundation
import SwiftData
import Testing
@testable import Keptang

private let calendar = Calendar.app

private func at(_ month: Int, _ day: Int, _ hour: Int = 12, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute))!
}

private let now = at(10, 18, 9)

private func receipt(_ key: String, _ shop: String, _ date: Date, _ total: Double, _ category: SpendCategory = .dining,
                     items: [String] = [], kind: ReceiptKind = .purchase, photo: Bool = false) -> GraphReceipt {
    GraphReceipt(key: key, shop: shop, date: date, total: total, kind: kind,
                 categories: kind.isBill ? [.utilities: total] : [category: total], items: items, hasPhoto: photo, rawText: "")
}

private let sample: [GraphReceipt] = [
    receipt("a1", "Café Amazon", at(10, 13, 8, 10), 65, items: ["ลาเต้เย็น"]),
    receipt("a2", "Café Amazon", at(10, 14, 8, 5), 55, items: ["อเมริกาโน่เย็น"]),
    receipt("a2dup", "Café Amazon", at(10, 14, 8, 9), 55, items: ["อเมริกาโน่เย็น"]),
    receipt("s1", "Starbucks", at(10, 15, 9, 30), 145, items: ["Caffè Latte Grande"]),
    receipt("l1", "Lotus's", at(10, 11, 17), 420, .groceries, items: ["นมจืด 2 ลิตร", "ไข่ไก่ แพ็ค 10"], photo: true),
    receipt("b1", "Big C", at(10, 4, 17), 380, .groceries, items: ["นมจืด 2 ลิตร", "ขนมปังโฮลวีท"]),
    receipt("u1", "Uniqlo", at(10, 10, 15), 390, .shopping, items: ["AIRism T-Shirt"]),
    receipt("m1", "การไฟฟ้านครหลวง (MEA)", at(9, 20, 18), 2_475, items: ["ค่าไฟฟ้า"], kind: .electricity),
    receipt("m2", "การไฟฟ้านครหลวง (MEA)", at(8, 20, 18), 2_539, items: ["ค่าไฟฟ้า"], kind: .electricity),
    receipt("w1", "AIS Fibre", at(9, 5, 9), 748, items: ["อินเทอร์เน็ตไฟเบอร์"], kind: .internet),
    receipt("w2", "AIS Fibre", at(10, 5, 9), 748, items: ["อินเทอร์เน็ตไฟเบอร์"], kind: .internet),
    receipt("w3", "AIS Fibre", at(8, 5, 9), 748, items: ["อินเทอร์เน็ตไฟเบอร์"], kind: .internet),
    receipt("x1", "", at(10, 12, 20), 99, .other),
]

@Suite("Spending graph")
struct SpendingGraphTests {
    let graph = SpendingGraph(receipts: sample)

    @Test("A duplicate receipt adds no node or edge")
    func duplicates() {
        #expect(graph.duplicates == ["a2dup"])
        #expect(graph.node(SpendingGraph.receiptID("a2dup")) == nil)
        #expect(!graph.edges.contains { $0.from == SpendingGraph.receiptID("a2dup") })
        #expect(graph.node("s:café amazon".replacingOccurrences(of: "é", with: "e"))?.count == 2)
    }

    @Test("Edges: each receipt to its shop, categories, items and photo")
    func edgeCounts() {
        let receipts = graph.nodes.filter { $0.kind == .receipt }
        #expect(receipts.count == sample.count - 1)
        let shopEdges = graph.edges.filter { [.shop, .unknownShop].contains(graph.node($0.to)?.kind) }
        #expect(shopEdges.count == receipts.count)
        let itemEdges = graph.edges.filter { graph.node($0.to)?.kind == .item }
        #expect(itemEdges.count == sample.filter { $0.key != "a2dup" }.reduce(0) { $0 + $1.items.count })
        #expect(graph.edges.filter { graph.node($0.to)?.kind == .photo }.count == 1)
        #expect(graph.node("i:นมจืด 2 ลิตร")?.count == 2, "an item bought at two shops connects them")
        #expect(graph.node(SpendingGraph.unknownShopID)?.count == 1)
        let utilities = graph.node("c:utilities")
        #expect(utilities?.amount == 7_258.0, "utilities: \(String(describing: utilities))")
        #expect(Set(graph.backlinks(of: "s:ais fibre").map(\.key)) == ["w1", "w2", "w3"])
    }

    @Test("Filters change only the view")
    func filters() {
        var filter = SpendingGraph.Filter()
        filter.range = .all
        let base = graph.filtered(filter, now: now).graph
        #expect(!base.nodes.contains { [.category, .item, .photo].contains($0.kind) })
        filter.showCategories = true
        filter.showItems = true
        filter.showPhotos = true
        let full = graph.filtered(filter, now: now).graph
        #expect(full.node("c:dining") != nil && full.node("i:นมจืด 2 ลิตร") != nil && full.node("p:l1") != nil)
        filter.existingOnly = true
        #expect(graph.filtered(filter, now: now).graph.node(SpendingGraph.unknownShopID) == nil)
        #expect(graph.nodes.count == SpendingGraph(receipts: sample).nodes.count)

        let month = graph.filtered(SpendingGraph.Filter(), now: now).graph
        #expect(month.node(SpendingGraph.receiptID("m2")) == nil, "1M leaves out August")
        #expect(graph.filtered(SpendingGraph.Filter(search: "shop:starbucks", range: .all), now: now).graph.nodes.filter { $0.kind == .receipt }.count == 1)
        #expect(graph.filtered(SpendingGraph.Filter(search: "category:groceries", range: .all), now: now).graph.nodes.filter { $0.kind == .receipt }.count == 2)
        #expect(graph.filtered(SpendingGraph.Filter(search: "748", range: .all), now: now).graph.nodes.filter { $0.kind == .receipt }.count == 3)
        #expect(graph.filtered(SpendingGraph.Filter(search: "14 oct", range: .all), now: now).graph.nodes.filter { $0.kind == .receipt }.count == 1)
    }

    @Test("Orphans share no shop or item with another receipt")
    func orphans() {
        var filter = SpendingGraph.Filter(range: .all)
        filter.showOrphans = false
        let shown = graph.filtered(filter, now: now).graph
        let ids = Set(shown.nodes.filter { $0.kind == .receipt }.compactMap(\.receiptKey))
        // Starbucks, Uniqlo and the unknown shop share nothing; Lotus's and Big C share milk.
        #expect(!ids.contains("s1") && !ids.contains("u1") && !ids.contains("x1"))
        #expect(ids.isSuperset(of: ["a1", "a2", "l1", "b1", "m1", "m2", "w1", "w2", "w3"]))
        #expect(shown.node("s:starbucks") == nil)
    }

    @Test("Local graph grows one step per depth")
    func localDepth() {
        var filter = SpendingGraph.Filter(range: .all)
        filter.showItems = true
        let center = SpendingGraph.receiptID("l1")
        func ids(_ depth: Int, neighbours: Bool = false) -> Set<String> {
            Set(graph.filtered(filter, local: SpendingGraph.Local(center: center, depth: depth, neighbourLinks: neighbours), now: now).graph.nodes.map(\.id))
        }
        #expect(ids(1) == [center, "s:lotus's", "i:นมจืด 2 ลิตร", "i:ไข่ไก่ แพ็ค 10"])
        #expect(ids(2) == ids(1).union([SpendingGraph.receiptID("b1")]))
        #expect(ids(3) == ids(2).union(["s:big c", "i:ขนมปังโฮลวีท"]))
        let local = graph.filtered(filter, local: SpendingGraph.Local(center: "s:ais fibre", depth: 1), now: now)
        #expect(local.distance[SpendingGraph.receiptID("w1")] == 1)
        let outOnly = graph.filtered(filter, local: SpendingGraph.Local(center: "s:ais fibre", depth: 1, incoming: false), now: now).graph
        #expect(outOnly.nodes.map(\.id) == ["s:ais fibre"], "a shop links nowhere itself")
    }
}

@Suite("Suggested links")
struct SuggestionTests {
    let suggester = LinkSuggester()

    private func suggestion(_ a: String, _ b: String, in list: [LinkSuggester.Suggestion]) -> LinkSuggester.Suggestion? {
        list.first { $0.pairKey == LinkSuggester.pairKey(a, b) }
    }

    @Test("Scores are deterministic and in range")
    func deterministic() {
        let first = suggester.suggestions(for: sample, excluding: ["a2dup"])
        let second = suggester.suggestions(for: sample.reversed(), excluding: ["a2dup"])
        #expect(first == second)
        #expect(first.allSatisfy { (0...1).contains($0.score) && !$0.reason.isEmpty })
        #expect(!first.contains { $0.a == "a2dup" || $0.b == "a2dup" }, "duplicates get no suggestions")
    }

    @Test("Coffee links to coffee across shops and languages")
    func coffee() throws {
        let list = suggester.suggestions(for: sample, excluding: ["a2dup"])
        let pair = try #require(suggestion("a1", "s1", in: list))
        #expect(pair.reason.contains("coffee"))
        #expect(pair.score >= LinkSuggester.defaultThreshold)
        #expect(suggestion("a1", "a2", in: list) == nil, "same shop is already linked through the shop")
    }

    @Test("Recurring bills of the same amount are suggested")
    func recurring() throws {
        let list = suggester.suggestions(for: sample, excluding: ["a2dup"])
        let internet = try #require(suggestion("w1", "w2", in: list))
        #expect(internet.reason.contains("every month"))
        #expect(suggestion("w1", "w3", in: list) != nil, "August and September are next in line")
        #expect(suggestion("w2", "w3", in: list) == nil, "August and October aren't")
        #expect(internet.score >= LinkSuggester.defaultThreshold)
        #expect(suggestion("m1", "m2", in: list) == nil, "different amounts at the same shop: the shop already links them")
    }

    @Test("Shared basket items link two supermarkets")
    func basket() throws {
        let list = suggester.suggestions(for: sample, excluding: ["a2dup"])
        let pair = try #require(suggestion("l1", "b1", in: list))
        #expect(pair.reason.contains("นมจืด"))
    }

    @Test("Unrelated receipts aren't suggested at the default strength")
    func unrelated() {
        let list = suggester.suggestions(for: sample, excluding: ["a2dup"]).filter { $0.score >= LinkSuggester.defaultThreshold }
        #expect(suggestion("u1", "m1", in: list) == nil)
        #expect(suggestion("a1", "u1", in: list) == nil)
        #expect(suggestion("s1", "l1", in: list) == nil)
    }

    @Test("The threshold decides which suggestions show")
    func threshold() {
        let graph = SpendingGraph(receipts: sample)
        let list = suggester.suggestions(for: sample, excluding: graph.duplicates)
        func count(_ threshold: Double) -> Int {
            graph.filtered(SpendingGraph.Filter(range: .all, minimumScore: threshold), suggestions: list, now: now).graph.edges.filter { $0.kind == .suggested }.count
        }
        #expect(count(0) >= count(0.5))
        #expect(count(0.5) >= count(0.9))
        #expect(count(1.01) == 0)
        var off = SpendingGraph.Filter(range: .all)
        off.showSuggestions = false
        #expect(graph.filtered(off, suggestions: list, now: now).graph.edges.allSatisfy { $0.kind == .link })
    }

    @Test("Confirmed links stay, dismissed ones never show")
    func decisions() throws {
        let graph = SpendingGraph(receipts: sample)
        let list = suggester.suggestions(for: sample, excluding: graph.duplicates)
        let pair = try #require(suggestion("a1", "s1", in: list))
        let filter = SpendingGraph.Filter(range: .all, minimumScore: 1.01)
        let confirmed = graph.filtered(filter, suggestions: list, decisions: [pair.pairKey: true], now: now).graph
        #expect(confirmed.edges.contains { $0.kind == .confirmed && Set([$0.from, $0.to]) == [SpendingGraph.receiptID("a1"), SpendingGraph.receiptID("s1")] })
        let dismissed = graph.filtered(SpendingGraph.Filter(range: .all, minimumScore: 0), suggestions: list, decisions: [pair.pairKey: false], now: now).graph
        #expect(!dismissed.edges.contains { $0.kind != .link && Set([$0.from, $0.to]) == [SpendingGraph.receiptID("a1"), SpendingGraph.receiptID("s1")] })
    }

    @Test("What the suggester makes of the app's sample data")
    @MainActor
    func sampleDataReport() throws {
        let container = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        SampleData.seed(in: context, now: now)
        let receipts = try context.fetch(FetchDescriptor<Receipt>(sortBy: [SortDescriptor(\.date)]))
        let graphReceipts = receipts.enumerated().map { $0.element.graphReceipt(key: String(format: "%04d", $0.offset)) }
        let byKey = Dictionary(uniqueKeysWithValues: graphReceipts.map { ($0.key, $0) })
        let list = suggester.suggestions(for: graphReceipts)
        let shown = list.filter { $0.score >= LinkSuggester.defaultThreshold }
        var perReceipt: [String: Int] = [:]
        for s in shown { perReceipt[s.a, default: 0] += 1; perReceipt[s.b, default: 0] += 1 }
        print("SAMPLE: \(graphReceipts.count) receipts, \(list.count) suggestions, \(shown.count) at ≥\(LinkSuggester.defaultThreshold); receipts with any: \(perReceipt.count); max per receipt \(perReceipt.values.max() ?? 0)")
        func describe(_ s: LinkSuggester.Suggestion) -> String {
            "\(byKey[s.a]!.shop) \(byKey[s.a]!.date.formatted(.dateTime.day().month(.abbreviated))) ↔ \(byKey[s.b]!.shop) \(byKey[s.b]!.date.formatted(.dateTime.day().month(.abbreviated))): \(s.score) \(s.reason)"
        }
        var seenKinds = Set<String>()
        for s in shown {
            let kind = [byKey[s.a]!.shop, byKey[s.b]!.shop].sorted().joined(separator: " + ")
            if seenKinds.insert(kind).inserted { print("SAMPLE PAIR \(describe(s))") }
        }
        // Spot checks of pairs that should and shouldn't connect.
        let amazon = graphReceipts.filter { $0.shop == "Café Amazon" }
        let starbucks = graphReceipts.filter { $0.shop == "Starbucks" }
        let uniqlo = graphReceipts.filter { $0.shop == "Uniqlo" }
        let bts = graphReceipts.filter { $0.shop == "BTS Skytrain" }
        let features = Dictionary(uniqueKeysWithValues: graphReceipts.map { ($0.key, suggester.features(of: $0)) })
        let vectors = Dictionary(uniqueKeysWithValues: zip(graphReceipts.map(\.key), LinkSuggester.tfidf(graphReceipts.map { features[$0.key]!.terms })))
        func pair(_ x: GraphReceipt?, _ y: GraphReceipt?) -> String {
            guard let x, let y else { return "n/a" }
            return suggester.score(features[x.key]!, features[y.key]!, vectors[x.key]!, vectors[y.key]!).map { "\($0.score) \($0.reason)" } ?? "no link (same shop)"
        }
        print("SAMPLE CHECK coffee Amazon↔Starbucks: \(pair(amazon.last, starbucks.last))")
        print("SAMPLE CHECK Uniqlo↔BTS: \(pair(uniqlo.last, bts.last))")
        print("SAMPLE CHECK Starbucks↔Uniqlo: \(pair(starbucks.last, uniqlo.last))")
        let mea = graphReceipts.filter { $0.kind == .electricity }
        let mwa = graphReceipts.filter { $0.kind == .water }
        print("SAMPLE CHECK power↔power: \(pair(mea.dropLast().last, mea.last))")
        print("SAMPLE CHECK power↔water: \(pair(mea.last, mwa.last))")
        #expect(!shown.isEmpty)
        #expect((perReceipt.values.max() ?? 0) <= LinkSuggester.perReceipt)
    }
}

@Suite("Link decisions and migration")
@MainActor
struct StoreTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("KeptangGraph-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("A dismissal is still there after reopening the store")
    func dismissPersists() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        do {
            let container = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            LinkDecision.set(false, for: "a|b", in: context)
            LinkDecision.set(true, for: "c|d", in: context)
            LinkDecision.set(false, for: "c|d", in: context)
        }
        let reopened = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self, configurations: ModelConfiguration(url: url))
        let decisions = try ModelContext(reopened).fetch(FetchDescriptor<LinkDecision>(sortBy: [SortDescriptor(\.pairKey)]))
        #expect(decisions.map(\.pairKey) == ["a|b", "c|d"])
        #expect(decisions.allSatisfy { !$0.confirmed })
    }

    @Test("Opening an older store adds link decisions and keeps every receipt")
    func migration() throws {
        let dir = try folder()
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        do {
            // The schema before this change: receipts and items only.
            let old = try ModelContainer(for: Receipt.self, LineItem.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(old)
            var draft = ParsedReceipt()
            draft.shopName = "Lotus's"
            draft.date = at(3, 1)
            draft.total = 224
            draft.rawText = "ยอดสุทธิ 224.00"
            draft.imageData = Data(repeating: 7, count: 200_000)
            draft.items = [ParsedItem(name: "นมจืด", total: 95, category: .groceries), ParsedItem(name: "ไข่ไก่", total: 129, category: .groceries)]
            Receipt.insert(draft, into: context)
            try context.save()
        }
        let new = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self, configurations: ModelConfiguration(url: url))
        let context = ModelContext(new)
        let receipts = try context.fetch(FetchDescriptor<Receipt>())
        #expect(receipts.count == 1)
        #expect(receipts.first?.items.count == 2)
        #expect(receipts.first?.imageData?.count == 200_000)
        #expect(receipts.first?.rawText == "ยอดสุทธิ 224.00")
        LinkDecision.set(true, for: "x|y", in: context)
        #expect(try context.fetchCount(FetchDescriptor<LinkDecision>()) == 1)
    }
}

@Suite("Receipt keys")
@MainActor
struct KeyTests {
    @Test("A receipt's graph key is the same every time and after reopening the store")
    func stableKey() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("KeptangKey-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("store.sqlite")
        var first = ""
        do {
            let container = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self, configurations: ModelConfiguration(url: url))
            let context = ModelContext(container)
            var draft = ParsedReceipt()
            draft.shopName = "Tops"
            draft.total = 120
            Receipt.insert(draft, into: context)
            try context.save()
            let receipt = try #require(try context.fetch(FetchDescriptor<Receipt>()).first)
            first = receipt.graphKey
            for _ in 0..<20 { #expect(receipt.graphKey == first) }
        }
        let reopened = try ModelContainer(for: Receipt.self, LineItem.self, LinkDecision.self, configurations: ModelConfiguration(url: url))
        let again = try #require(try ModelContext(reopened).fetch(FetchDescriptor<Receipt>()).first)
        #expect(again.graphKey == first)
    }
}

@Suite("Graph search")
struct GraphSearchTests {
    let graph = SpendingGraph(receipts: sample)

    @Test("Shop names come first, then the receipts that match, newest first")
    func shopsThenReceipts() {
        let found = graph.search("amazon")
        #expect(found.first?.kind == .shop)
        #expect(found.first?.title == "Café Amazon")
        let receipts = found.filter { $0.kind == .receipt }
        #expect(!receipts.isEmpty)
        let dates = receipts.compactMap(\.lastDate)
        #expect(dates == dates.sorted(by: >))
    }

    @Test("Items, Thai words, amounts and field terms all find receipts")
    func kindsOfSearch() {
        #expect(graph.search("นมจืด").contains { $0.kind == .receipt })
        #expect(graph.search("748").filter { $0.kind == .receipt }.count == 3)
        #expect(graph.search("shop:uniqlo").map(\.kind) == [.receipt])
        #expect(graph.search("").isEmpty)
        #expect(graph.search("   ").isEmpty)
        #expect(graph.search("zzzz-nothing").isEmpty)
    }
}
