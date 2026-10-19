import SwiftData
import SwiftUI

/// Settings → Chat bots: where the cloud is, linking Discord with a 6-digit code, the inbox,
/// the opt-in summary and deleting everything the cloud holds.
struct ChatBotsView: View {
    @Environment(\.modelContext) private var context
    @AppStorage("cloudURL") private var cloudURL = ""
    @AppStorage("cloudKey") private var cloudKey = ""
    @AppStorage("shareSummary") private var shareSummary = false
    @State private var editingCloud = false
    @State private var code: String?
    @State private var codeMade: Date?
    @State private var working = false
    @State private var problem: String?
    @State private var confirmingDelete = false
    private var cloud: CloudSync { CloudSync.shared }

    var body: some View {
        CardPage {
            if !cloud.isConfigured || editingCloud {
                cloudSettings
            } else {
                discord
                inbox
                sharing
                CardSection(title: "Cloud", note: "Connected to \(URL(string: cloudURL)?.host() ?? cloudURL).", color: .sky) {
                    RowButton(title: "Change cloud settings", symbol: "gearshape") { editingCloud = true }
                    RowButton(title: "Delete my cloud data", symbol: "trash", destructive: true) { confirmingDelete = true }
                }
            }
            if let message = problem ?? cloud.problem {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.up)
                    .padding(.horizontal, 4)
            }
        }
        .navigationTitle("Chat bots")
        .navigationBarTitleDisplayMode(.inline)
        .task { await cloud.refreshLinks() }
        .confirmationDialog("Delete everything Snapceipt keeps in the cloud?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete cloud data", role: .destructive) {
                Task {
                    await cloud.deleteEverything()
                    shareSummary = false
                    code = nil
                }
            }
        } message: {
            Text("Unlinks Discord and removes waiting photos, the inbox and the shared summary. Receipts on this phone stay.")
        }
    }

    // MARK: Cloud

    private var cloudSettings: some View {
        CardSection(title: "Connect the cloud", note: "From Supabase → Project Settings → API: the Project URL and the anon public key. Never the service key: that one stays on the bot's computer.", color: .sky) {
            LabeledContent("Project URL") {
                TextField("https://xxxx.supabase.co", text: $cloudURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .multilineTextAlignment(.trailing)
            }
            LabeledContent("Anon key") {
                TextField("eyJhbGciOi…", text: $cloudKey)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .multilineTextAlignment(.trailing)
            }
            Button {
                editingCloud = false
                Task { await cloud.refreshLinks() }
            } label: {
                Label("Save", systemImage: "checkmark")
            }
            .buttonStyle(BlockButtonStyle(prominent: true))
            .disabled(CloudConfig.current == nil)
            .padding(.vertical, 8)
        }
    }

    // MARK: Discord

    private var discordLink: LinkedAccount? { cloud.linked.first { $0.provider == "discord" } }

    private var discord: some View {
        CardSection(title: "Discord", note: "Send the Snapceipt bot “Pop corn 60” or a receipt photo, and it lands here.", color: .purple) {
            if let link = discordLink {
                Label("Linked\(link.displayName.map { " as \($0)" } ?? "")", systemImage: "checkmark.circle.fill")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.down)
                RowButton(title: "Disconnect Discord", symbol: "link.badge.plus", destructive: true) {
                    Task { await cloud.unlink("discord") }
                }
            } else if let code {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send this to the Snapceipt bot in Discord:").font(.subheadline).foregroundStyle(Theme.muted)
                    Text("/link \(code)")
                        .font(Theme.figure(.title))
                        .fontWeight(.bold)
                        .foregroundStyle(Theme.ink)
                        .textSelection(.enabled)
                        .accessibilityLabel("Slash link \(code.map { String($0) }.joined(separator: " "))")
                    if let codeMade {
                        Text("Works until \(codeMade.addingTimeInterval(600).formatted(date: .omitted, time: .shortened)).")
                            .font(.footnote).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 8)
                Button { UIPasteboard.general.string = "/link \(code)" } label: { Label("Copy", systemImage: "doc.on.doc") }
                    .buttonStyle(BlockButtonStyle())
                    .padding(.vertical, 6)
                RowButton(title: "I’ve sent it, check again", symbol: "arrow.clockwise") {
                    Task { await cloud.refreshLinks(); if discordLink != nil { self.code = nil } }
                }
                RowButton(title: "New code", symbol: "number") { makeCode() }
            } else {
                Button(action: makeCode) {
                    Label(working ? "Making a code…" : "Connect Discord", systemImage: "link")
                }
                .buttonStyle(BlockButtonStyle(prominent: true))
                .disabled(working)
                .padding(.vertical, 8)
            }
        }
    }

    private func makeCode() {
        working = true
        Task {
            do {
                code = try await cloud.linkCode()
                codeMade = .now
                problem = nil
            } catch {
                problem = error.localizedDescription
            }
            working = false
        }
    }

    // MARK: Inbox and sharing

    private var inbox: some View {
        CardSection(title: "Inbox", color: .lime) {
            LabeledContent("Photos waiting", value: "\(cloud.waitingPhotos.count)")
            LabeledContent("Last check", value: cloud.lastSync?.formatted(date: .omitted, time: .shortened) ?? "Not yet")
            if cloud.lastImported > 0 {
                Text("Added \(cloud.lastImported) from the chat last time.").font(.footnote).foregroundStyle(Theme.muted)
            }
            RowButton(title: cloud.isSyncing ? "Checking…" : "Check now", symbol: "tray.and.arrow.down") {
                Task { await cloud.sync(context) }
            }
        }
    }

    private var sharing: some View {
        CardSection(title: "Answers in the chat", note: "Lets the bot answer /summary and /goal. Shares this month's totals per category, money in and your goal — no single receipts, shops or photos.", color: .yellow) {
            Toggle("Share a monthly summary", isOn: $shareSummary)
                .onChange(of: shareSummary) { _, on in
                    Task { if on { await cloud.sync(context) } else { await cloud.stopSharingSummary() } }
                }
        }
    }
}
