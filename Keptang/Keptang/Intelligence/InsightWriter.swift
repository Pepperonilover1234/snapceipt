import Foundation
import FoundationModels

@Generable
struct AISpendingSummary {
    @Guide(description: "One friendly, specific sentence about the person's spending pattern, under 25 words")
    var headline: String

    @Guide(description: "Two or three short, practical money-saving tips based only on the facts given, each under 20 words")
    var tips: [String]
}

struct SpendingSummary: Equatable {
    var headline: String
    var tips: [String]
    var writtenByAI: Bool
}

/// Turns the numbers the analyzer found into plain words with the on-device model.
enum InsightWriter {
    static func summary(facts: [String]) async -> SpendingSummary {
        guard !facts.isEmpty else {
            return SpendingSummary(headline: "Scan a few receipts and Snapceipt will start spotting patterns.", tips: [], writtenByAI: false)
        }
        guard OnDeviceAI.isAvailable else { return fallback(facts) }
        do {
            let session = LanguageModelSession(instructions: """
                You are a friendly money coach for a working adult in Thailand. \
                Use only the facts given. Amounts are Thai baht; write them like ฿1,200. Be specific and brief.
                """)
            let response = try await session.respond(
                to: "Spending facts:\n" + facts.map { "- " + $0 }.joined(separator: "\n"),
                generating: AISpendingSummary.self
            )
            return SpendingSummary(headline: response.content.headline, tips: Array(response.content.tips.prefix(3)), writtenByAI: true)
        } catch {
            return fallback(facts)
        }
    }

    private static func fallback(_ facts: [String]) -> SpendingSummary {
        SpendingSummary(headline: facts[0], tips: Array(facts.dropFirst().prefix(3)), writtenByAI: false)
    }
}
