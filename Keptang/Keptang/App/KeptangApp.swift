import SwiftData
import SwiftUI

@main
struct KeptangApp: App {
    init() {
        Theme.styleNavigationBars()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [Receipt.self, LineItem.self, LinkDecision.self])
    }
}

enum AppTab: String, Hashable {
    case overview, receipts, scan, bills, plan

    /// `-tab analysis` works as well as `-tab plan`.
    init?(launchName: String) {
        self.init(rawValue: launchName == "analysis" ? "plan" : launchName)
    }
}

/// Moves between tabs from deep inside a screen, e.g. "Show in graph" on a receipt.
@MainActor @Observable
final class AppRouter {
    var tab: AppTab = LaunchOption.string("tab").flatMap(AppTab.init(launchName:)) ?? .overview
    /// The graph node Data analysis should open its Local graph on.
    var graphCenter: String?

    func showInGraph(_ node: String) {
        graphCenter = node
        tab = .plan
    }
}

/// Launch arguments for demos and screenshots, e.g. `-tab bills -range 1Y`.
/// Arguments like `-name value` land in UserDefaults' argument domain.
enum LaunchOption {
    static func string(_ name: String) -> String? { UserDefaults.standard.string(forKey: name) }
}

struct RootView: View {
    @Environment(\.modelContext) private var context
    @State private var router = AppRouter()
    @AppStorage("appearance") private var appearance: Appearance = .system
    /// Changing it rebuilds the screens so every colour and font picks up the new theme.
    @AppStorage("skin") private var skin: Skin = .console
    @AppStorage("colour") private var colour: Paint = .console
    @State private var booting = LaunchOption.string("boot") != "NO"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        @Bindable var router = router
        TabView(selection: $router.tab) {
            Tab("Overview", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.overview) {
                NavigationStack { OverviewView(tab: $router.tab) }
                    .environment(\.pageAccent, Theme.accent)
            }
            Tab("Receipts", systemImage: "list.bullet.rectangle.portrait", value: AppTab.receipts) {
                NavigationStack { ReceiptsView() }
                    .environment(\.pageAccent, Theme.accent)
            }
            Tab("Add", systemImage: "plus", value: AppTab.scan) {
                NavigationStack { ScanView(onSaved: { router.tab = .receipts }) }
                    .environment(\.pageAccent, Theme.accent)
            }
            .badge(CloudSync.shared.waitingPhotos.count + SharedInbox.shared.items.count)
            Tab("Bills", systemImage: "bolt.fill", value: AppTab.bills) {
                NavigationStack { BillsView() }
                    .environment(\.pageAccent, Theme.accent)
            }
            Tab("Data analysis", systemImage: "sparkles", value: AppTab.plan) {
                NavigationStack { PlanView() }
                    .environment(\.pageAccent, Theme.accent)
            }
        }
        .id("\(skin.rawValue)-\(colour.rawValue)")
        .overlay {
            if booting && !reduceMotion { BootScreen(isShowing: $booting).transition(.opacity) }
        }
        .environment(router)
        .tabViewStyle(.sidebarAdaptable)
        .tint(Theme.ink)
        .toggleStyle(CheckboxToggleStyle())
        .onChange(of: appearance, initial: true) { appearance.apply() }
        .task {
            appearance.apply()
            SampleData.seedIfNeeded(in: context)
            if SharedInbox.shared.refresh() { router.tab = .scan }
            await CloudSync.shared.sync(context)
        }
        .onChange(of: scenePhase) { _, phase in
            // Whatever was sent through the chat while the app was closed comes in when it opens.
            if phase == .active {
                // Photos shared in from another app open on Add, read and waiting for a check.
                if SharedInbox.shared.refresh() { router.tab = .scan }
                Task { await CloudSync.shared.sync(context) }
            }
        }
        .task(id: scenePhase) {
            // While the app is open and Discord is linked, look for new entries every 15 seconds,
            // so something sent from another device shows up without reopening the app.
            while scenePhase == .active, !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard scenePhase == .active, !Task.isCancelled, CloudSync.shared.isLinked else { continue }
                await CloudSync.shared.sync(context)
            }
        }
        .overlay(alignment: .top) {
            if !CloudSync.shared.justAdded.isEmpty { chatBanner }
        }
        .onOpenURL { url in
            guard url.scheme == "snapceipt" else { return }
            SharedInbox.shared.refresh()
            router.tab = .scan
        }
    }

    /// "Added from Discord: ฿200.00 noodle", for a few seconds after the chat sends something in.
    private var chatBanner: some View {
        let added = CloudSync.shared.justAdded
        return HStack(spacing: 10) {
            Image(systemName: "bubble.left.and.text.bubble.right.fill").foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text("Added from Discord").font(.subheadline.weight(.bold)).foregroundStyle(Theme.ink)
                Text(added.prefix(3).joined(separator: " · ") + (added.count > 3 ? " +\(added.count - 3)" : ""))
                    .font(.footnote).foregroundStyle(Theme.muted).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button { router.tab = .receipts; CloudSync.shared.clearJustAdded() } label: {
                Text("See").font(.subheadline.weight(.bold)).foregroundStyle(Theme.accentText).frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .block(radius: 16)
        .padding(.horizontal)
        .padding(.top, 4)
        .frame(maxWidth: 520)
        .transition(.move(edge: .top).combined(with: .opacity))
        .accessibilityElement(children: .combine)
        .task {
            try? await Task.sleep(for: .seconds(5))
            withAnimation { CloudSync.shared.clearJustAdded() }
        }
    }
}
