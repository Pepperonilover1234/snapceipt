import Foundation

/// Where the cloud is: the Supabase project URL and its public (anon) key. The anon key is meant to
/// be in apps; the database's row-level security decides what it can see. Set in Settings → Chat bots,
/// or with the `-cloudURL` and `-cloudKey` launch arguments.
struct CloudConfig: Equatable {
    var url: String
    var anonKey: String

    static var current: CloudConfig? {
        let defaults = UserDefaults.standard
        let url = (defaults.string(forKey: "cloudURL") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let key = (defaults.string(forKey: "cloudKey") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let api = apiURL(url), !key.isEmpty else { return nil }
        return CloudConfig(url: api, anonKey: key)
    }

    /// The project's API address. The dashboard page's address ("supabase.com/dashboard/project/abcd")
    /// is turned into it ("https://abcd.supabase.co"), since that's the one people tend to copy.
    static func apiURL(_ text: String) -> String? {
        if let match = text.firstMatch(of: /supabase\.com\/dashboard\/project\/([a-z0-9]+)/) {
            return "https://\(match.1).supabase.co"
        }
        guard let parsed = URL(string: text), parsed.scheme == "https", parsed.host() != nil else { return nil }
        var trimmed = text
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        return trimmed
    }
}

/// The signed-in cloud user: an anonymous Supabase account made for this phone the first time it
/// connects. No email or password; the tokens stay in the Keychain.
struct CloudSession: Codable, Equatable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
    var userID: String

    private static let key = "session"

    static func load() -> CloudSession? {
        Keychain.data(for: key).flatMap { try? JSONDecoder().decode(CloudSession.self, from: $0) }
    }

    func save() { Keychain.set(try? JSONEncoder().encode(self), for: Self.key) }

    static func clear() { Keychain.set(nil, for: key) }
}

/// One thing sent through a bot, as the cloud keeps it.
struct InboxRow: Decodable, Identifiable, Equatable {
    struct Parsed: Codable, Equatable {
        struct Item: Codable, Equatable {
            var name: String
            var amount: Double
            var category: String
        }
        var flow: String
        var items: [Item]
        var source: String?
        var date: String
        var language: String?
    }

    var id: String
    var origin: String
    var kind: String
    var rawText: String?
    var photoPath: String?
    var parsed: Parsed?
    var status: String
    var createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, origin, kind, parsed, status
        case rawText = "raw_text"
        case photoPath = "photo_path"
        case createdAt = "created_at"
    }

    var created: Date { CloudClient.date(from: createdAt) ?? .now }
}

struct LinkedAccount: Decodable, Equatable {
    var provider: String
    var displayName: String?
    var linkedAt: String

    enum CodingKeys: String, CodingKey {
        case provider
        case displayName = "display_name"
        case linkedAt = "linked_at"
    }
}

/// The monthly totals the person may choose to share, so the bot can answer /summary and /goal.
struct CloudSummary: Encodable, Equatable {
    struct Category: Encodable, Equatable {
        var category: String
        var amount: Double
    }
    var userID: String
    var month: String
    var spent: Double
    var income: Double
    var goal: Double
    var perDay: Double
    var daysLeft: Int
    var byCategory: [Category]

    enum CodingKeys: String, CodingKey {
        case month, spent, income, goal
        case userID = "user_id"
        case perDay = "per_day"
        case daysLeft = "days_left"
        case byCategory = "by_category"
    }
}

enum CloudError: LocalizedError {
    case notConfigured
    case http(Int, String)

    var errorDescription: String? {
        switch self {
        case .notConfigured: "Add the Supabase project URL and key first."
        case let .http(code, body): "The cloud answered \(code): \(body.prefix(200))"
        }
    }
}

/// Talks to Supabase over its plain web API: sign-in, the database (PostgREST) and storage.
struct CloudClient {
    let config: CloudConfig
    var session: URLSession = .shared

    // MARK: Sign-in

    /// The saved session, refreshed when it's about to run out, or a new anonymous account.
    func signedIn() async throws -> CloudSession {
        if let saved = CloudSession.load() {
            if saved.expiresAt > Date.now.addingTimeInterval(60) { return saved }
            // Refreshing keeps the same account, so links to Discord stay. If it fails (offline, say)
            // the error comes back rather than a new account quietly replacing the linked one.
            return try await auth(path: "token?grant_type=refresh_token", body: ["refresh_token": saved.refreshToken])
        }
        return try await auth(path: "signup", body: [:])
    }

    private func auth(path: String, body: [String: String]) async throws -> CloudSession {
        struct Response: Decodable {
            struct User: Decodable { var id: String }
            var access_token: String
            var refresh_token: String
            var expires_in: Double
            var user: User
        }
        let data = try await send("auth/v1/\(path)", method: "POST", json: body, token: nil)
        let response = try JSONDecoder().decode(Response.self, from: data)
        let session = CloudSession(accessToken: response.access_token, refreshToken: response.refresh_token,
                                   expiresAt: .now.addingTimeInterval(response.expires_in), userID: response.user.id)
        session.save()
        return session
    }

    // MARK: Linking

    func createLinkCode() async throws -> String {
        let session = try await signedIn()
        let data = try await send("rest/v1/rpc/create_link_code", method: "POST", json: [String: String](), token: session.accessToken)
        return try JSONDecoder().decode(String.self, from: data)
    }

    func linkedAccounts() async throws -> [LinkedAccount] {
        guard CloudSession.load() != nil else { return [] }
        let session = try await signedIn()
        let data = try await send("rest/v1/linked_accounts?select=provider,display_name,linked_at", token: session.accessToken)
        return try JSONDecoder().decode([LinkedAccount].self, from: data)
    }

    func unlink(provider: String) async throws {
        let session = try await signedIn()
        _ = try await send("rest/v1/linked_accounts?provider=eq.\(provider)", method: "DELETE", token: session.accessToken)
    }

    // MARK: Inbox

    /// Typed entries the person saved in the chat, and photos waiting to be read.
    func waitingInbox() async throws -> [InboxRow] {
        let session = try await signedIn()
        let filter = "or=(status.eq.confirmed,and(kind.eq.photo,status.eq.pending))"
        let data = try await send("rest/v1/inbox?select=*&\(filter)&order=created_at.asc", token: session.accessToken)
        return try JSONDecoder().decode([InboxRow].self, from: data)
    }

    func mark(_ id: String, status: String) async throws {
        let session = try await signedIn()
        _ = try await send("rest/v1/inbox?id=eq.\(id)", method: "PATCH", json: ["status": status], token: session.accessToken)
    }

    func downloadPhoto(_ path: String) async throws -> Data {
        let session = try await signedIn()
        return try await send("storage/v1/object/authenticated/receipts/\(path)", token: session.accessToken)
    }

    func deletePhotos(_ paths: [String]) async throws {
        guard !paths.isEmpty else { return }
        let session = try await signedIn()
        _ = try await send("storage/v1/object/receipts", method: "DELETE", json: ["prefixes": paths], token: session.accessToken)
    }

    // MARK: Summary and clean-up

    func upload(_ summary: CloudSummary) async throws {
        let session = try await signedIn()
        var body = summary
        body.userID = session.userID
        _ = try await send("rest/v1/summaries", method: "POST", json: body, token: session.accessToken,
                           headers: ["Prefer": "resolution=merge-duplicates"])
    }

    func removeSummary() async throws {
        let session = try await signedIn()
        _ = try await send("rest/v1/summaries?user_id=eq.\(session.userID)", method: "DELETE", token: session.accessToken)
    }

    /// Everything about this person in the cloud: photos, inbox, summary and links.
    func deleteEverything() async throws {
        guard CloudSession.load() != nil else { return }
        let session = try await signedIn()
        struct Object: Decodable { var name: String }
        struct List: Encodable { var prefix: String; var limit = 1000 }
        let listed = try await send("storage/v1/object/list/receipts", method: "POST",
                                    json: List(prefix: session.userID), token: session.accessToken)
        let names = (try? JSONDecoder().decode([Object].self, from: listed))?.map { "\(session.userID)/\($0.name)" } ?? []
        try await deletePhotos(names)
        _ = try await send("rest/v1/rpc/delete_my_cloud_data", method: "POST", json: [String: String](), token: session.accessToken)
        CloudSession.clear()
    }

    // MARK: Requests

    @discardableResult
    private func send(_ path: String, method: String = "GET", json: (any Encodable)? = nil, token: String?,
                      headers: [String: String] = [:]) async throws -> Data {
        guard let url = URL(string: "\(config.url)/\(path)") else { throw CloudError.notConfigured }
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.httpMethod = method
        request.setValue(config.anonKey, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(token ?? config.anonKey)", forHTTPHeaderField: "Authorization")
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        if let json {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(json)
        }
        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw CloudError.http(code, String(decoding: data, as: UTF8.self)) }
        return data
    }

    /// "2026-10-18T11:30:00.123456+00:00" or "2026-10-18T11:30:00.000Z": the fraction is dropped,
    /// since Postgres gives six digits and the formatter wants three.
    static func date(from text: String) -> Date? {
        let trimmed = text.replacingOccurrences(of: #"\.\d+"#, with: "", options: .regularExpression)
        return ISO8601DateFormatter().date(from: trimmed)
    }
}
