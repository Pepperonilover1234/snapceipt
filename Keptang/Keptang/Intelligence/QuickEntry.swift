import Foundation
import FoundationModels
import NaturalLanguage

/// Something typed instead of scanned: "Pop corn 60", "ข้าวมันไก่ 50 เมื่อวาน", "เงินเดือน 30000".
struct QuickEntry: Equatable {
    enum Flow: String, Equatable {
        case moneyOut, moneyIn
    }

    enum Reader: String, Equatable {
        case appleIntelligence = "Apple Intelligence and text rules"
        case textRules = "On-device text rules"
    }

    var flow: Flow
    var items: [QuickItem]
    /// Where money in came from; ignored for money out.
    var source: IncomeSource
    var date: Date
    var text: String
    var reader: Reader
    /// "Thai", "English" or "Thai and English".
    var language: String

    var total: Double { items.reduce(0) { $0 + $1.amount } }

    /// Nothing read yet.
    static let empty = QuickEntry(flow: .moneyOut, items: [], source: .other, date: .now, text: "",
                                  reader: .textRules, language: "")
}

struct QuickItem: Identifiable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double
    var category: SpendCategory
    /// What the app picked, so a change can be learned.
    var suggested: SpendCategory
}

/// Reads a typed line in Thai or English with rules that always work offline. Numbers only ever
/// come from what was typed.
enum QuickEntryRules {
    static func read(_ text: String, now: Date = .now, calendar: Calendar = .app,
                     learner: CategoryLearner = .shared) -> QuickEntry {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        var working = MerchantCategorizer.normalize(trimmed)

        // Money in or out.
        let flow = flow(of: working)
        let source = incomeSource(in: working) ?? .other
        if working.hasPrefix("+") || working.hasPrefix("-") { working.removeFirst() }

        // When: "yesterday", "เมื่อวาน"…, taken out so they don't end up in the name.
        var daysAgo = 0
        for (words, days) in dateWords {
            for word in words where working.contains(word) {
                daysAgo = max(daysAgo, days)
                working = working.replacingOccurrences(of: word, with: " ")
            }
        }
        let date = daysAgo == 0 ? now
            : calendar.date(bySettingHour: 12, minute: 0, second: 0,
                            of: calendar.date(byAdding: .day, value: -daysAgo, to: now)!)!

        // What and how much.
        var items: [QuickItem] = []
        var pendingName = ""
        for chunk in chunks(of: working) {
            let (name, amount) = nameAndAmount(in: chunk)
            guard let amount else {
                pendingName = [pendingName, name].filter { !$0.isEmpty }.joined(separator: " & ")
                continue
            }
            let fullName = [pendingName, name].filter { !$0.isEmpty }.joined(separator: " & ")
            pendingName = ""
            let category = category(for: fullName, aiGuess: nil, learner: learner)
            items.append(QuickItem(name: fullName, amount: amount, category: category, suggested: category))
        }
        if !pendingName.isEmpty, items.isEmpty {
            let category = category(for: pendingName, aiGuess: nil, learner: learner)
            items.append(QuickItem(name: pendingName, amount: 0, category: category, suggested: category))
        }
        if flow == .moneyIn {
            // Money in is one amount; the words become its name.
            let total = items.reduce(0) { $0 + $1.amount }
            let name = items.map(\.name).filter { !$0.isEmpty }.joined(separator: ", ")
            items = [QuickItem(name: name.isEmpty ? source.name : name, amount: total, category: .other, suggested: .other)]
        }
        return QuickEntry(flow: flow, items: items, source: source, date: date, text: trimmed,
                          reader: .textRules, language: language(of: trimmed))
    }

    /// The best category for a typed name: learned fixes, the merchant, the Create ML model,
    /// Apple Intelligence's guess, then keywords; tried again with the spaces taken out so
    /// "pop corn" finds "popcorn".
    static func category(for name: String, aiGuess: SpendCategory?, learner: CategoryLearner = .shared) -> SpendCategory {
        let first = MerchantCategorizer.category(forItem: name, shopName: name, aiGuess: aiGuess, learner: learner)
        guard first == .other else { return first }
        let joined = name.replacingOccurrences(of: " ", with: "")
        guard joined != name else { return first }
        return MerchantCategorizer.category(forItem: joined, shopName: joined, aiGuess: aiGuess, learner: learner)
    }

    static func flow(of text: String) -> QuickEntry.Flow {
        let text = text.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("+") { return .moneyIn }
        if text.hasPrefix("-") { return .moneyOut }
        return incomeSource(in: text) == nil ? .moneyOut : .moneyIn
    }

    /// The income source the words name, if any. "ร้านขายยา" (a pharmacy) is a shop, not a sale.
    static func incomeSource(in text: String) -> IncomeSource? {
        let text = MerchantCategorizer.normalize(text)
            .replacingOccurrences(of: "ร้านขาย", with: " ")
            .replacingOccurrences(of: "ขายยา", with: " ")
        let words = " " + text.replacingOccurrences(of: #"[^a-z0-9']+"#, with: " ", options: .regularExpression) + " "
        for (source, keywords) in IncomeSource.keywords {
            for keyword in keywords {
                let isLatin = keyword.unicodeScalars.allSatisfy { $0.value < 0x0E00 }
                if isLatin ? words.contains(" \(keyword) ") : text.contains(keyword) { return source }
            }
        }
        return nil
    }

    private static let dateWords: [([String], Int)] = [
        (["เมื่อวานซืน", "day before yesterday"], 2),
        (["เมื่อวาน", "เมื่อคืน", "yesterday", "last night"], 1),
        (["วันนี้", "today", "tonight", "คืนนี้"], 0),
    ]

    /// Pieces split at commas, new lines and semicolons, then at "and", "และ" and "+" where
    /// both sides have a price ("coffee and cake 125" stays one piece).
    static func chunks(of text: String) -> [String] {
        // "1,290" is one number, not two items.
        let grouped = text.replacingOccurrences(of: #"(\d),(?=\d{3}(?!\d))"#, with: "$1", options: .regularExpression)
        let hard = grouped.components(separatedBy: CharacterSet(charactersIn: ",;\n、"))
        return hard.flatMap { part -> [String] in
            guard amounts(in: part).count > 1 else { return [part] }
            let soft = part.replacingOccurrences(of: #"\s+(and|&|\+)\s+|และ"#, with: "\u{1}", options: .regularExpression)
            return soft.components(separatedBy: "\u{1}")
        }
        .map { $0.trimmingCharacters(in: .whitespaces) }
        .filter { !$0.isEmpty }
    }

    private static let amountPattern = #"(\d[\d,]*(?:\.\d+)?)\s*(k|พัน|หมื่น|แสน)?(?![\d])"#

    private static func amounts(in text: String) -> [NSTextCheckingResult] {
        let regex = try! NSRegularExpression(pattern: amountPattern, options: [.caseInsensitive])
        return regex.matches(in: text, range: NSRange(text.startIndex..., in: text))
    }

    /// The last number in a piece is its price ("2 coffee 90" costs 90); the rest is its name.
    static func nameAndAmount(in chunk: String) -> (String, Double?) {
        guard let match = amounts(in: chunk).last, let numberRange = Range(match.range(at: 1), in: chunk) else {
            return (cleanName(chunk), nil)
        }
        var value = Double(chunk[numberRange].replacingOccurrences(of: ",", with: "")) ?? 0
        if let unitRange = Range(match.range(at: 2), in: chunk) {
            switch chunk[unitRange].lowercased() {
            case "k", "พัน": value *= 1_000
            case "หมื่น": value *= 10_000
            case "แสน": value *= 100_000
            default: break
            }
        }
        var name = chunk
        name.removeSubrange(Range(match.range, in: chunk)!)
        return (cleanName(name), value)
    }

    private static func cleanName(_ text: String) -> String {
        var name = text
        for word in ["บาท", "baht", "bht", "thb", "฿", "ค่า "] {
            name = name.replacingOccurrences(of: word, with: " ", options: .caseInsensitive)
        }
        return name
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "-:x×@=.")))
    }

    /// Which languages were typed, from the script and NaturalLanguage's guess.
    static func language(of text: String) -> String {
        let hasThai = text.unicodeScalars.contains { (0x0E00...0x0E7F).contains($0.value) }
        let hasLatin = text.unicodeScalars.contains { CharacterSet.letters.contains($0) && $0.value < 0x0250 }
        if hasThai && hasLatin { return "Thai and English" }
        if hasThai { return "Thai" }
        if hasLatin {
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            if let language = recognizer.dominantLanguage, language != .english, language != .undetermined {
                return Locale.current.localizedString(forLanguageCode: language.rawValue) ?? "English"
            }
            return "English"
        }
        return "numbers only"
    }
}

// MARK: - Apple Intelligence

@Generable
struct AIQuickEntry {
    @Guide(description: "moneyIn when the person received money (salary, sold something, refund, gift, interest). moneyOut when they spent or paid.")
    var direction: AIDirection

    @Guide(description: "Each thing bought, or the one income, with its amount in baht exactly as typed. Keep the person's own words for the name, in Thai or English.")
    var items: [AIQuickItem]

    @Guide(description: "Where the money came from, for money in. other for money out.")
    var incomeSource: AIIncomeSource

    @Guide(description: "How many days before today this happened: 0 for today or when not said, 1 for yesterday (เมื่อวาน).")
    var daysAgo: Int
}

@Generable
struct AIQuickItem {
    var name: String
    var amount: Double
    @Guide(description: "What it is")
    var category: AICategory
}

@Generable
enum AIDirection {
    case moneyOut
    case moneyIn
}

@Generable
enum AIIncomeSource {
    case salary, freelance, sales, gift, refund, investment, other

    var source: IncomeSource {
        switch self {
        case .salary: .salary
        case .freelance: .freelance
        case .sales: .sales
        case .gift: .gift
        case .refund: .refund
        case .investment: .investment
        case .other: .other
        }
    }
}

enum QuickEntryReader {
    static let instructions = """
        You read short notes people type into a Thai budgeting app, in Thai or English, such as \
        "Pop corn 60", "ข้าวมันไก่ 50 เมื่อวาน" or "เงินเดือน 30000". Amounts are Thai baht. \
        Only use numbers that were typed; never invent amounts.
        """

    /// The rules' reading, improved by Apple Intelligence where it's on: it decides money in or out,
    /// the categories and the day. Amounts and names stay as typed unless the rules found none.
    static func read(_ text: String, now: Date = .now, calendar: Calendar = .app) async -> QuickEntry {
        var entry = QuickEntryRules.read(text, now: now, calendar: calendar)
        guard OnDeviceAI.isAvailable, !entry.text.isEmpty else { return entry }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(to: "Note: \(entry.text)", generating: AIQuickEntry.self,
                                                     options: GenerationOptions(samplingMode: .greedy))
            merge(response.content, into: &entry, now: now, calendar: calendar)
            entry.reader = .appleIntelligence
        } catch {
            // The rules' reading stands.
            #if DEBUG
            print("QuickEntry AI failed: \(error)")
            #endif
        }
        return entry
    }

    static func merge(_ ai: AIQuickEntry, into entry: inout QuickEntry, now: Date, calendar: Calendar) {
        let typedNumbers = Set(QuickEntryRules.chunks(of: entry.text).compactMap { QuickEntryRules.nameAndAmount(in: $0).1 })
        let aiFlow: QuickEntry.Flow = ai.direction == .moneyIn ? .moneyIn : .moneyOut
        // A clear sign or income word from the rules wins over the model.
        let rulesSure = entry.text.hasPrefix("+") || entry.text.hasPrefix("-") || QuickEntryRules.incomeSource(in: entry.text) != nil
        let flow = rulesSure ? entry.flow : aiFlow

        if flow == .moneyIn {
            let source = entry.flow == .moneyIn && entry.source != .other ? entry.source : ai.incomeSource.source
            let total = entry.total > 0 ? entry.total : ai.items.map(\.amount).filter { typedNumbers.contains($0) }.reduce(0, +)
            let name = entry.items.first?.name ?? ai.items.first?.name ?? source.name
            entry.items = [QuickItem(name: name.isEmpty ? source.name : name, amount: total, category: .other, suggested: .other)]
            entry.source = source
        } else if ai.items.count == entry.items.count {
            for index in entry.items.indices {
                let aiGuess = ai.items[index].category.spendCategory
                let category = QuickEntryRules.category(for: entry.items[index].name, aiGuess: aiGuess)
                entry.items[index].category = category
                entry.items[index].suggested = category
            }
        } else if entry.items.isEmpty || entry.items.contains(where: { $0.amount == 0 }) {
            // The rules couldn't split it; take the model's items whose amounts were really typed.
            let usable = ai.items.filter { typedNumbers.contains($0.amount) }
            if !usable.isEmpty {
                entry.items = usable.map { item in
                    let category = QuickEntryRules.category(for: item.name, aiGuess: item.category.spendCategory)
                    return QuickItem(name: item.name, amount: item.amount, category: category, suggested: category)
                }
            }
        }
        entry.flow = flow
        let sameDay = calendar.isDate(entry.date, inSameDayAs: now)
        if sameDay, (1...31).contains(ai.daysAgo) {
            entry.date = calendar.date(bySettingHour: 12, minute: 0, second: 0,
                                       of: calendar.date(byAdding: .day, value: -ai.daysAgo, to: now)!)!
        }
    }
}
