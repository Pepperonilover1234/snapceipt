import Foundation
import Observation
import SwiftData

/// Brings in what was sent through a chat bot, and shares the opt-in monthly summary.
///
/// - Typed entries the person already checked and saved in the chat are added straight away.
/// - Photos wait in the Add tab's inbox: Snapceipt reads them on the phone and the person
///   checks them like any scan; then the cloud copy is deleted.
@MainActor @Observable
final class CloudSync {
    static let shared = CloudSync()

    struct WaitingPhoto: Identifiable, Equatable {
        var id: String
        var path: String
        var origin: String
        var caption: String?
        var sent: Date
    }

    private(set) var waitingPhotos: [WaitingPhoto] = []
    private(set) var linked: [LinkedAccount] = []
    private(set) var lastSync: Date?
    private(set) var lastImported = 0
    /// What the last check brought in, for the banner: "noodle ฿200.00".
    private(set) var justAdded: [String] = []
    /// True while something is linked, so the open app keeps checking.
    var isLinked: Bool { !linked.isEmpty }
    private(set) var problem: String?
    private(set) var isSyncing = false

    var isConfigured: Bool { CloudConfig.current != nil }
    var client: CloudClient? { CloudConfig.current.map { CloudClient(config: $0) } }

    /// Checks the inbox (when there is a cloud and something is linked) and shares the summary.
    func sync(_ context: ModelContext) async {
        guard let client, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }
        do {
            linked = try await client.linkedAccounts()
            guard CloudSession.load() != nil else { return }
            let rows = try await client.waitingInbox()
            var imported = 0
            var added: [String] = []
            for row in rows where row.kind == "text" && row.status == "confirmed" {
                if let entry = Self.entry(from: row) {
                    let receipt = QuickEntryStore.save(entry, in: context)
                    receipt.reader = row.origin == "line" ? "LINE" : "Discord"
                    try context.save()
                    try await client.mark(row.id, status: "imported")
                    imported += 1
                    added.append("\(entry.flow == .moneyIn ? "+" : "")\(entry.total.baht) \(receipt.shopName)")
                }
            }
            waitingPhotos = rows.filter { $0.kind == "photo" && $0.status == "pending" }.compactMap { row in
                row.photoPath.map { WaitingPhoto(id: row.id, path: $0, origin: row.origin, caption: row.rawText, sent: row.created) }
            }
            lastImported = imported
            if !added.isEmpty { justAdded = added }
            if UserDefaults.standard.bool(forKey: "shareSummary") { try await shareSummary(context) }
            lastSync = .now
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    func clearJustAdded() { justAdded = [] }

    func photoData(_ photo: WaitingPhoto) async throws -> Data {
        guard let client else { throw CloudError.notConfigured }
        return try await client.downloadPhoto(photo.path)
    }

    /// After the photo was read and saved on the phone: mark it done and delete the cloud copy.
    func finished(_ photo: WaitingPhoto, saved: Bool) async {
        guard let client else { return }
        try? await client.mark(photo.id, status: saved ? "imported" : "cancelled")
        try? await client.deletePhotos([photo.path])
        waitingPhotos.removeAll { $0.id == photo.id }
    }

    func linkCode() async throws -> String {
        guard let client else { throw CloudError.notConfigured }
        return try await client.createLinkCode()
    }

    func refreshLinks() async {
        guard let client else { return }
        do {
            linked = try await client.linkedAccounts()
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    func unlink(_ provider: String) async {
        guard let client else { return }
        do {
            try await client.unlink(provider: provider)
            linked.removeAll { $0.provider == provider }
        } catch {
            problem = error.localizedDescription
        }
    }

    func stopSharingSummary() async {
        try? await client?.removeSummary()
    }

    func deleteEverything() async {
        guard let client else { return }
        do {
            try await client.deleteEverything()
            linked = []
            waitingPhotos = []
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
    }

    private func shareSummary(_ context: ModelContext) async throws {
        guard let client else { return }
        let all = (try? context.fetch(FetchDescriptor<Receipt>())) ?? []
        let goal = UserDefaults.standard.double(forKey: "moneyGoal")
        try await client.upload(Self.summary(of: all, goal: goal, now: .now))
    }

    // MARK: - Pure parts, tested

    /// A checked chat entry as the same kind of reading the Type it screen makes.
    nonisolated static func entry(from row: InboxRow) -> QuickEntry? {
        guard let parsed = row.parsed, !parsed.items.isEmpty else { return nil }
        let flow: QuickEntry.Flow = parsed.flow == "moneyIn" ? .moneyIn : .moneyOut
        let items = parsed.items.map { item in
            let category = SpendCategory(rawValue: item.category) ?? .other
            return QuickItem(name: item.name, amount: item.amount, category: category, suggested: category)
        }
        guard items.reduce(0, { $0 + $1.amount }) > 0 else { return nil }
        return QuickEntry(
            flow: flow,
            items: items,
            source: parsed.source.flatMap(IncomeSource.init(rawValue:)) ?? .other,
            date: CloudClient.date(from: parsed.date) ?? row.created,
            text: row.rawText ?? items.map(\.name).joined(separator: ", "),
            reader: .textRules,
            language: parsed.language ?? ""
        )
    }

    /// This month's totals: money out by category, money in, and the goal's per day.
    static func summary(of receipts: [Receipt], goal: Double, now: Date, calendar: Calendar = .app) -> CloudSummary {
        let month = calendar.dateInterval(of: .month, for: now)!
        let inMonth = receipts.filter { $0.date >= month.start && $0.date < month.end }
        let spending = SpendingAnalyzer(inMonth.filter { !$0.isIncome }.map(ReceiptSnapshot.init), calendar: calendar)
        let spent = spending.total(in: month)
        let income = inMonth.filter(\.isIncome).reduce(0) { $0 + $1.total }
        let progress = goal > 0 ? MoneyGoal(goal: goal, spent: spent, month: month, now: now, calendar: calendar) : nil
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return CloudSummary(
            userID: "",
            month: formatter.string(from: month.start),
            spent: (spent * 100).rounded() / 100,
            income: (income * 100).rounded() / 100,
            goal: goal,
            perDay: ((progress?.perDay ?? 0) * 100).rounded() / 100,
            daysLeft: progress?.daysLeft ?? 0,
            byCategory: spending.categoryTotals(in: month).map { .init(category: $0.category.rawValue, amount: ($0.amount * 100).rounded() / 100) }
        )
    }
}
