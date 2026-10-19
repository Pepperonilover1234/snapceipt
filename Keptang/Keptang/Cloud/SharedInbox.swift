import Foundation
import Observation

/// Photos shared into Snapceipt from other apps ("Share → Snapceipt"). The share extension drops
/// JPEGs into the folder the app and extension share; the app shows them on the Add tab, reads the
/// newest arrival straight away, and deletes each file once it's saved or thrown away.
@MainActor @Observable
final class SharedInbox {
    static let shared = SharedInbox()
    nonisolated static let group = "group.com.pepperonilover1234.keptang"

    struct Item: Identifiable, Equatable {
        var url: URL
        var arrived: Date
        var id: URL { url }
    }

    private(set) var items: [Item] = []
    /// A photo that arrived since the app last looked, to read right away.
    var toOpen: Item?
    private var seen: Set<URL> = []

    private let folder: URL?

    init(folder: URL? = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedInbox.group)?
            .appendingPathComponent("SharedInbox", isDirectory: true)) {
        self.folder = folder
    }

    /// Looks for new files. Returns true when something new arrived (so the app can go to Add).
    @discardableResult
    func refresh() -> Bool {
        guard let folder else { return false }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey])) ?? []
        items = files
            .filter { ["jpg", "jpeg", "png", "heic"].contains($0.pathExtension.lowercased()) }
            .map { url in
                let date = (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .now
                return Item(url: url, arrived: date)
            }
            .sorted { $0.arrived < $1.arrived }
        let fresh = items.filter { !seen.contains($0.url) }
        seen.formUnion(items.map(\.url))
        if let first = fresh.first {
            toOpen = first
            return true
        }
        return false
    }

    func data(_ item: Item) -> Data? { try? Data(contentsOf: item.url) }

    func remove(_ item: Item) {
        try? FileManager.default.removeItem(at: item.url)
        items.removeAll { $0.url == item.url }
        if toOpen == item { toOpen = nil }
    }
}
