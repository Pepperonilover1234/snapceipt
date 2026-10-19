import Foundation
import NaturalLanguage

/// Suggests which receipts belong together, on the device, beyond the links the receipts already
/// share (shop, items, category). Nothing leaves the phone.
///
/// Each receipt becomes text: the shop, the items, the category, a few lines read from the photo,
/// and "concepts" from a small Thai–English lexicon (ลาเต้ and latte are both coffee), split into
/// words with NaturalLanguage's tokenizer, which segments Thai. Receipts are compared by TF-IDF cosine
/// similarity, plus Apple's sentence embedding when the device has one, and three learned patterns:
/// the same outing (bought within a few hours on one day), a recurring purchase (the same amount at a
/// weekly or monthly interval) and a similar basket (shared items). The score is 0 to 1.
struct LinkSuggester {
    struct Suggestion: Hashable, Identifiable {
        let a: String
        let b: String
        let score: Double
        let reason: String
        var pairKey: String { LinkSuggester.pairKey(a, b) }
        var id: String { pairKey }
    }

    /// Where the "Match strength" slider starts: a handful of links per receipt on real spending.
    static let defaultThreshold = 0.55
    /// At most this many suggestions per receipt, strongest first.
    static let perReceipt = 3

    static func pairKey(_ a: String, _ b: String) -> String { a < b ? "\(a)|\(b)" : "\(b)|\(a)" }

    /// Turns English text into a vector, when the device has a sentence embedding. Nil otherwise.
    var embed: ((String) -> [Double]?)?
    var calendar: Calendar = .app

    // MARK: - Features

    struct Features {
        let receipt: GraphReceipt
        let shopKey: String
        let terms: [String: Double]
        let concepts: Set<String>
        let items: Set<String>
        let embedding: [Double]?
        let isWeekdayMorning: Bool
    }

    /// Words that carry the same meaning in Thai and English, so a latte at Café Amazon and one at
    /// Starbucks look alike. Checked as substrings of the lower-cased shop and item names.
    static let concepts: [(String, [String])] = [
        ("coffee", ["กาแฟ", "ลาเต้", "อเมริกาโน่", "คาปูชิโน่", "เอสเปรสโซ่", "มอคค่า", "coffee", "latte", "americano", "cappuccino", "espresso", "mocha", "frappuccino", "caffè", "starbucks", "café amazon", "cafe amazon"]),
        ("tea", ["ชาไทย", "ชาเขียว", "ชานม", "มัทฉะ", "thai tea", "green tea", "matcha", "milk tea"]),
        ("bakery", ["ครัวซองต์", "เค้ก", "ขนมปัง", "croissant", "cake", "cheesecake", "toast", "bakery", "kakigori", "honey toast"]),
        ("meal", ["ข้าวมัน", "ข้าวผัด", "ข้าวขา", "ข้าวกะเพรา", "ก๋วยเตี๋ยว", "ผัดไทย", "ส้มตำ", "กะเพรา", "noodle", "fried rice", "pad thai", "food court", "ฟู้ดคอร์ท"]),
        ("hotpot", ["ชาบู", "สุกี้", "ชุดผัก", "เนื้อสไลซ์", "หมูนุ่ม", "ติ่มซำ", "เป็ดย่าง", "bar b q plaza", "mk restaurants"]),
        ("ride", ["ค่าโดยสาร", "bts", "mrt", "grab ride", "taxi", "แท็กซี่", "fare"]),
        ("fuel", ["แก๊สโซฮอล์", "เบนซิน", "ดีเซล", "gasohol", "diesel", "fuel", "ptt station", "shell"]),
        ("electricity bill", ["ค่าไฟ", "ไฟฟ้า", "electricity", "(mea)", "(pea)"]),
        ("water bill", ["ค่าน้ำ", "ประปา", "water bill", "(mwa)", "(pwa)"]),
        ("internet bill", ["อินเทอร์เน็ต", "internet", "fibre", "fiber", "ais fibre", "true online", "3bb"]),
        ("groceries", ["นมจืด", "ไข่ไก่", "ข้าวหอม", "อกไก่", "หมูสับ", "ผักกาด", "มะเขือเทศ", "กล้วย", "ส้ม", "น้ำปลา", "น้ำมันพืช", "โยเกิร์ต", "milk", "eggs", "yogurt", "salmon", "แซลมอน"]),
        ("household", ["ทิชชู่", "ผงซักฟอก", "น้ำยาล้างจาน", "ถุงขยะ", "tissue", "detergent"]),
        ("personal care", ["ยาสีฟัน", "แชมพู", "กันแดด", "โฟมล้างหน้า", "วิตามิน", "shampoo", "sunscreen", "vitamin", "toothpaste"]),
        ("clothes", ["เสื้อ", "กางเกง", "รองเท้า", "กระเป๋า", "shirt", "t-shirt", "jeans", "socks", "parka", "sneakers"]),
        ("movie", ["ตั๋วหนัง", "ป๊อปคอร์น", "movie", "popcorn", "cineplex", "cinema"]),
        ("gadget", ["ipad", "iphone", "pencil", "laptop", "airpods", "macbook"]),
        ("home goods", ["หลอดไฟ", "ปลั๊ก", "กระทะ", "พัดลม", "กล่องเก็บของ", "homepro"]),
    ]

    static func concepts(in text: String) -> Set<String> {
        let lower = text.lowercased()
        return Set(concepts.filter { $0.1.contains(where: lower.contains) }.map(\.0))
    }

    /// Words worth comparing: no numbers, prices or receipt boilerplate.
    static let stopWords: Set<String> = ["total", "vat", "tax", "invoice", "receipt", "cash", "change", "thank", "you", "รวม", "ยอด", "สุทธิ",
                                         "ภาษี", "เงินสด", "เงินทอน", "ใบเสร็จ", "บาท", "baht", "co", "ltd", "the", "and", "id", "no", "กก", "ก"]

    static func words(in text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .word)
        tokenizer.string = text
        var words: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            let word = text[range].lowercased()
            if word.count >= 2, !word.allSatisfy({ $0.isNumber || $0.isPunctuation }), !stopWords.contains(word) {
                words.append(word)
            }
            return true
        }
        return words
    }

    func features(of receipt: GraphReceipt) -> Features {
        let ocr = receipt.rawText.split(separator: "\n").prefix(25).joined(separator: " ")
        let description = ([receipt.shop] + receipt.items).joined(separator: " ")
        let concepts = receipt.kind.isBill ? Self.concepts(in: description).union(["bills"]) : Self.concepts(in: description)
        var counts: [String: Double] = [:]
        for word in Self.words(in: description + " " + ocr) { counts[word, default: 0] += 1 }
        // Concepts and the main category count double: they're what makes two receipts alike.
        for concept in concepts { counts["#" + concept, default: 0] += 2 }
        counts["@" + receipt.mainCategory.rawValue, default: 0] += 1
        let hour = calendar.component(.hour, from: receipt.date)
        let weekday = calendar.component(.weekday, from: receipt.date)
        let english = (concepts.sorted() + [receipt.mainCategory.name]).joined(separator: ", ")
        return Features(
            receipt: receipt,
            shopKey: MerchantCategorizer.normalize(receipt.shop),
            terms: counts,
            concepts: concepts,
            items: Set(receipt.items.map(CategoryLearner.normalize)),
            embedding: embed?(english),
            isWeekdayMorning: (6..<11).contains(hour) && weekday != 1 && weekday != 7
        )
    }

    // MARK: - Scoring

    /// Every receipt's strongest suggestions. Duplicates (as the graph drops them) get none.
    func suggestions(for receipts: [GraphReceipt], excluding duplicates: Set<String> = [], cache: [String: Features] = [:]) -> [Suggestion] {
        let features = receipts.filter { !duplicates.contains($0.key) }.sorted { ($0.date, $0.key) < ($1.date, $1.key) }
            .map { cache[$0.key] ?? self.features(of: $0) }
        let vectors = Self.tfidf(features.map(\.terms))
        let series = Self.recurringSeries(features.map(\.receipt))
        var candidates: [Suggestion] = []
        for i in features.indices {
            for j in features.indices where j > i {
                guard let suggestion = score(features[i], features[j], vectors[i], vectors[j], series: series), suggestion.score > 0.2 else { continue }
                candidates.append(suggestion)
            }
        }
        // Strongest first, and no receipt takes part in more than `perReceipt` suggestions.
        var used: [String: Int] = [:]
        var chosen: [Suggestion] = []
        for suggestion in candidates.sorted(by: { ($0.score, $1.pairKey) > ($1.score, $0.pairKey) }) {
            guard used[suggestion.a, default: 0] < Self.perReceipt, used[suggestion.b, default: 0] < Self.perReceipt else { continue }
            used[suggestion.a, default: 0] += 1
            used[suggestion.b, default: 0] += 1
            chosen.append(suggestion)
        }
        return chosen
    }

    /// Next-in-line pairs of a recurring purchase: the same amount at the same shop, about a month
    /// apart, at least three times in a row (a subscription or a fixed bill), so a one-off coincidence
    /// doesn't count.
    static func recurringSeries(_ receipts: [GraphReceipt], calendar: Calendar = .app) -> Set<String> {
        var pairs = Set<String>()
        let groups = Dictionary(grouping: receipts) { "\(MerchantCategorizer.normalize($0.shop))|\(Int($0.total.rounded()))" }
        for group in groups.values where group.count >= 3 {
            let sorted = group.sorted { $0.date < $1.date }
            var run: [GraphReceipt] = [sorted[0]]
            func flush() {
                if run.count >= 3 { for (x, y) in zip(run, run.dropFirst()) { pairs.insert(pairKey(x.key, y.key)) } }
            }
            for next in sorted.dropFirst() {
                let days = next.date.timeIntervalSince(run.last!.date) / 86_400
                if (26...35).contains(days) { run.append(next) } else { flush(); run = [next] }
            }
            flush()
        }
        return pairs
    }

    /// TF-IDF weights, each vector scaled to length 1.
    static func tfidf(_ documents: [[String: Double]]) -> [[String: Double]] {
        var frequency: [String: Double] = [:]
        for document in documents { for term in document.keys { frequency[term, default: 0] += 1 } }
        let n = Double(max(documents.count, 1))
        return documents.map { document in
            var vector = document.reduce(into: [String: Double]()) { result, entry in
                result[entry.key] = (1 + log(entry.value)) * log((n + 1) / (frequency[entry.key, default: 0] + 1)) + 0.01
            }
            let length = vector.values.reduce(0) { $0 + $1 * $1 }.squareRoot()
            if length > 0 { for key in vector.keys { vector[key]! /= length } }
            return vector
        }
    }

    static func cosine(_ a: [String: Double], _ b: [String: Double]) -> Double {
        let (small, large) = a.count < b.count ? (a, b) : (b, a)
        return small.reduce(0) { $0 + $1.value * (large[$1.key] ?? 0) }
    }

    static func cosine(_ a: [Double], _ b: [Double]) -> Double {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        let dot = zip(a, b).reduce(0) { $0 + $1.0 * $1.1 }
        let length = (a.reduce(0) { $0 + $1 * $1 } * b.reduce(0) { $0 + $1 * $1 }).squareRoot()
        return length > 0 ? dot / length : 0
    }

    func score(_ x: Features, _ y: Features, _ vx: [String: Double], _ vy: [String: Double], series: Set<String> = []) -> Suggestion? {
        let a = x.receipt, b = y.receipt
        let sameShop = x.shopKey == y.shopKey && !x.shopKey.isEmpty
        let gap = abs(a.date.timeIntervalSince(b.date))
        let days = gap / 86_400

        // Patterns learned from how people spend.
        let recurring = series.contains(Self.pairKey(a.key, b.key))
        let outing = calendar.isDate(a.date, inSameDayAs: b.date) && gap <= 3 * 3_600
        // Shops already link their own receipts; only a repeating amount is news there.
        if sameShop && !recurring { return nil }

        var text = Self.cosine(vx, vy)
        if let ex = x.embedding, let ey = y.embedding {
            // Sentence embeddings rate any two phrases about 0.4 alike, so only the part above that counts.
            text = 0.7 * text + 0.3 * min(1, max(0, (Self.cosine(ex, ey) - 0.4) / 0.6))
        }
        let shared = x.items.intersection(y.items)
        let basket = shared.isEmpty ? 0 : Double(shared.count) / Double(x.items.union(y.items).count)
        let allConcepts = x.concepts.union(y.concepts)
        let conceptMatch = allConcepts.isEmpty ? 0 : Double(x.concepts.intersection(y.concepts).count) / Double(allConcepts.count)
        let morning = x.isWeekdayMorning && y.isWeekdayMorning && conceptMatch > 0
        // Of two equally alike pairs, the one closer in time is the better suggestion.
        let recency = 0.05 * exp(-days / 30)

        let score = min(1, 0.45 * conceptMatch + 0.35 * text + 0.3 * basket + (outing ? 0.15 : 0) + (recurring ? 0.6 : 0)
                        + (morning ? 0.1 : 0) + recency)
        guard score > 0 else { return nil }

        var reason: String
        let common = x.concepts.intersection(y.concepts).sorted()
        if recurring {
            reason = "Same amount (\(a.total.baht)) every month" + (sameShop ? " at \(a.shop)" : "")
        } else if !shared.isEmpty && basket >= 0.2 {
            reason = "Both have " + shared.sorted().prefix(2).joined(separator: " and ")
        } else if !common.isEmpty {
            reason = "Both are " + common.prefix(2).joined(separator: " and ") + (morning ? " on weekday mornings" : "")
        } else {
            reason = "Similar receipts (\(a.mainCategory.name))"
        }
        if outing && !recurring {
            let minutes = Int(gap / 60)
            reason += minutes < 90 ? ", bought \(minutes) min apart" : ", same outing"
        }
        let (first, second) = a.key < b.key ? (a.key, b.key) : (b.key, a.key)
        return Suggestion(a: first, b: second, score: (score * 1000).rounded() / 1000, reason: reason)
    }
}

/// Runs the suggester off the main thread and keeps each receipt's features, so adding or editing
/// one receipt only re-reads that receipt.
actor LinkSuggestionEngine {
    static let shared = LinkSuggestionEngine()

    private var cache: [String: (fingerprint: Int, features: LinkSuggester.Features)] = [:]
    private var suggester = LinkSuggester()
    private var embeddingChecked = false

    func suggestions(for receipts: [GraphReceipt], excluding duplicates: Set<String>) -> [LinkSuggester.Suggestion] {
        if !embeddingChecked {
            embeddingChecked = true
            suggester.embed = SentenceEmbedder.make()
        }
        var features: [String: LinkSuggester.Features] = [:]
        for receipt in receipts where !duplicates.contains(receipt.key) {
            let fingerprint = receipt.hashValue
            if let cached = cache[receipt.key], cached.fingerprint == fingerprint {
                features[receipt.key] = cached.features
            } else {
                let fresh = suggester.features(of: receipt)
                cache[receipt.key] = (fingerprint, fresh)
                features[receipt.key] = fresh
            }
        }
        let live = Set(receipts.map(\.key))
        cache = cache.filter { live.contains($0.key) }
        return suggester.suggestions(for: receipts, excluding: duplicates, cache: features)
    }

    var embeddingName: String { SentenceEmbedder.name }
}

/// Apple's on-device text embeddings: the contextual embedding when its assets are on the device,
/// otherwise the built-in English sentence embedding, otherwise none (TF-IDF carries on alone).
enum SentenceEmbedder {
    nonisolated(unsafe) private(set) static var name = "TF-IDF only"

    static func make() -> ((String) -> [Double]?)? {
        if let contextual = NLContextualEmbedding(language: .english) {
            if contextual.hasAvailableAssets, (try? contextual.load()) != nil {
                name = "Contextual embedding (English) + TF-IDF"
                return { text in
                    guard let result = try? contextual.embeddingResult(for: text, language: .english) else { return nil }
                    var sum = [Double](repeating: 0, count: contextual.dimension)
                    var count = 0.0
                    result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
                        for i in sum.indices where i < vector.count { sum[i] += vector[i] }
                        count += 1
                        return true
                    }
                    return count > 0 ? sum.map { $0 / count } : nil
                }
            } else {
                // Ask for the model in the background; next launch can use it.
                contextual.requestAssets { _, _ in }
            }
        }
        if let sentence = NLEmbedding.sentenceEmbedding(for: .english) {
            name = "Sentence embedding (English) + TF-IDF"
            return { sentence.vector(for: $0) }
        }
        return nil
    }
}
