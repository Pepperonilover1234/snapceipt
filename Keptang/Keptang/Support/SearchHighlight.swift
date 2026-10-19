import SwiftUI

/// Finds what the person searched for inside a piece of text, so it can be marked.
enum SearchHighlight {
    /// Every place `query` appears in `text`, ignoring case, accents and width; Thai matches as typed.
    static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        let needle = query.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty, !text.isEmpty else { return [] }
        var found: [Range<String.Index>] = []
        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], range: start..<text.endIndex) {
            found.append(range)
            start = range.upperBound
        }
        return found
    }

    /// The text with every match in bold on an orange wash, so it shows by weight as well as colour.
    static func attributed(_ text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        for range in ranges(of: query, in: text) {
            guard let lower = AttributedString.Index(range.lowerBound, within: result),
                  let upper = AttributedString.Index(range.upperBound, within: result) else { continue }
            result[lower..<upper].backgroundColor = Theme.accent.opacity(0.28)
            result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
        }
        return result
    }
}

extension EnvironmentValues {
    /// What the person is searching for, so rows can mark it.
    @Entry var searchHighlight: String = ""
}
