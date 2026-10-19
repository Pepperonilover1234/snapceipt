import SwiftUI

/// The money goal, pinned at the top of Overview: one thick solid bar of this month's
/// spending against the goal, a tick where spending should be by today, and what's left per day.
/// Tap it to set or change the goal.
struct MoneyGoalBar: View {
    /// This calendar month's total spending, all categories.
    let spent: Double
    let lastMonth: Double
    let month: DateInterval
    /// True while the chart shows one category, so the bar says it's tracking everything.
    let tracksAllWhileFiltered: Bool
    /// Inside another panel: no background or padding of its own.
    var embedded = false
    @AppStorage("moneyGoal") private var goalAmount = 0.0
    @State private var editing = LaunchOption.string("goalSheet") == "YES"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// About 22pt at the default text size, growing with Dynamic Type.
    @ScaledMetric(relativeTo: .headline) private var barHeight: CGFloat = 38

    var body: some View {
        Button { editing = true } label: {
            if goalAmount > 0 {
                meter(MoneyGoal(goal: goalAmount, spent: spent, month: month, now: .now))
            } else {
                emptyKey
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, embedded ? 0 : 12)
        .padding(.vertical, embedded ? 0 : 8)
        .background(embedded ? Color.clear : Theme.paper)
        .sheet(isPresented: $editing) {
            MoneyGoalSheet(goal: $goalAmount, spent: spent, lastMonth: lastMonth)
                .presentationDetents([.medium, .large])
        }
    }

    private var emptyKey: some View {
        HStack(spacing: 10) {
            LED(on: false)
            Text("money goal").font(Theme.label).foregroundStyle(Theme.muted)
            Spacer(minLength: 8)
            Label("set a money goal", systemImage: "plus")
                .font(.system(.footnote, design: Skin.current.design, weight: .semibold))
                .foregroundStyle(Theme.onAccent)
                .padding(.horizontal, 10)
                .frame(minHeight: 32)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Set a money goal")
        .accessibilityHint("Sets how much you want to spend this month")
    }

    private func colour(_ state: MoneyGoal.State) -> Color {
        switch state {
        case .onPace: Theme.keyGreen
        case .ahead: Theme.accent
        case .over: Theme.candleUp
        }
    }

    private func symbol(_ state: MoneyGoal.State) -> String {
        switch state {
        case .onPace: "checkmark"
        case .ahead: "exclamationmark"
        case .over: "xmark"
        }
    }

    private func meter(_ goal: MoneyGoal) -> some View {
        let tint = colour(goal.state)
        return VStack(alignment: .leading, spacing: 6) {
            title(tint: tint)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Rectangle().fill(Theme.line.opacity(0.6))
                    Rectangle().fill(tint).frame(width: proxy.size.width * min(goal.fraction, 1))
                }
                .overlay(Rectangle().strokeBorder(Theme.ink.opacity(0.55), lineWidth: 1))
            }
            .frame(height: barHeight)
            .animation(reduceMotion ? nil : .snappy, value: goal.fraction)
            figures(goal)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(goal.spoken)
        .accessibilityHint("Changes the money goal")
    }

    private func title(tint: Color) -> some View {
        HStack(spacing: 6) {
            LED(on: true, colour: tint)
            Text(Skin.current == .console || Skin.current == .gruv ? Theme.cased("money goal 01") : Theme.cased("money goal")).font(Theme.label).foregroundStyle(Theme.ink)
            if tracksAllWhileFiltered {
                Text("· all spending").font(Theme.smallLabel).foregroundStyle(Theme.muted)
            }
        }
    }

    /// Under the bar: per day for the days left, what's left, then spent / goal and the percent.
    private func figures(_ goal: MoneyGoal) -> some View {
        let days = "\(goal.daysLeft) day\(goal.daysLeft == 1 ? "" : "s")"
        let perDay = HStack(alignment: .firstTextBaseline, spacing: 5) {
            if goal.state == .over {
                Text("over by \(goal.overBy.bahtWhole)").font(Theme.figure(.title3)).fontWeight(.bold).foregroundStyle(Theme.up)
                Text("· \(days) to go").font(.system(.subheadline, design: Skin.current.design, weight: .semibold)).foregroundStyle(Theme.muted)
            } else {
                Text("\(goal.perDay.bahtWhole)/day").font(Theme.figure(.title3)).fontWeight(.bold).foregroundStyle(Theme.ink)
                Text("for \(days)").font(.system(.subheadline, design: Skin.current.design, weight: .semibold)).foregroundStyle(Theme.ink)
            }
        }
        // Over the goal, "over by" already says it; "฿0 left" would only repeat it.
        let left = Text(goal.state == .over ? "" : "\(goal.left.bahtWhole) left")
            .font(Theme.figure(.title3)).fontWeight(.bold).foregroundStyle(Theme.ink)
        let totals = HStack(spacing: 6) {
            Text("\(goal.spent.bahtWhole) / \(goal.goal.bahtWhole)").foregroundStyle(Theme.muted)
            Label(goal.fraction.percent, systemImage: symbol(goal.state))
                .labelStyle(.titleAndIcon)
                .foregroundStyle(goal.state == .over ? Theme.up : goal.state == .ahead ? Theme.accentText : Theme.down)
        }
        .font(Theme.figure(.subheadline))
        return VStack(alignment: .leading, spacing: 2) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) { perDay; Spacer(minLength: 8); left }
                VStack(alignment: .leading, spacing: 2) { perDay; left }
            }
            totals
        }
        .lineLimit(1)
        .minimumScaleFactor(0.75)
    }
}

/// Set, change or remove the money goal.
struct MoneyGoalSheet: View {
    @Binding var goal: Double
    let spent: Double
    let lastMonth: Double
    @State private var draft = 0.0
    @Environment(\.dismiss) private var dismiss

    private var presets: [(String, Double)] {
        var keys: [(String, Double)] = [("฿5k", 5_000), ("฿10k", 10_000), ("฿15k", 15_000), ("฿20k", 20_000)]
        if let last = MoneyGoal.suggestion(fromLastMonth: lastMonth) { keys.append(("last month", last)) }
        return keys
    }

    var body: some View {
        NavigationStack {
            CardPage {
                CardSection(title: "Monthly limit", note: "Spending this month: \(spent.baht). The bar turns orange when you're ahead of pace and red past the goal.") {
                    LabeledContent("Goal") { BahtField(title: "Money goal", value: $draft, fractionDigits: 0, style: .headline) }
                    HStack(spacing: 8) {
                        ParameterLabel(number: 1, text: "presets")
                        Spacer()
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(presets, id: \.0) { title, value in
                                Button { draft = value } label: {
                                    VStack(spacing: 3) {
                                        LED(on: draft == value)
                                        Text(title)
                                            .font(.system(.footnote, design: Skin.current.design, weight: .semibold))
                                            .foregroundStyle(draft == value ? Theme.ink : Theme.muted)
                                    }
                                    .padding(.horizontal, 12)
                                    .frame(minWidth: 56, minHeight: 48)
                                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(draft == value ? Theme.ink.opacity(0.5) : Theme.line, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(title == "last month" ? "Last month's spending, \(value.bahtWhole)" : value.bahtWhole)
                            }
                        }
                    }
                    Stepper("Fine adjust: ±฿500", value: $draft, in: 0...10_000_000, step: 500)
                }
                Button { goal = draft; dismiss() } label: { Text("save goal") }
                    .buttonStyle(BlockButtonStyle(prominent: true))
                    .disabled(draft <= 0)
                if goal > 0 {
                    Button(role: .destructive) { goal = 0; dismiss() } label: { Text("remove goal") }
                        .buttonStyle(BlockButtonStyle())
                }
            }
            .navigationTitle("Money goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .onAppear { draft = goal > 0 ? goal : (MoneyGoal.suggestion(fromLastMonth: lastMonth) ?? 10_000) }
    }
}

/// The money goal as any layout wants to draw it: the label gets this month's goal (or nil when
/// none is set), and a tap opens the goal sheet.
struct GoalButton<Label: View>: View {
    let spent: Double
    let lastMonth: Double
    let month: DateInterval
    @ViewBuilder let label: (MoneyGoal?) -> Label
    @AppStorage("moneyGoal") private var goalAmount = 0.0
    @State private var editing = LaunchOption.string("goalSheet") == "YES"

    var body: some View {
        let goal = goalAmount > 0 ? MoneyGoal(goal: goalAmount, spent: spent, month: month, now: .now) : nil
        Button { editing = true } label: { label(goal).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(goal?.spoken ?? "Set a money goal")
            .accessibilityHint(goal == nil ? "Sets how much you want to spend this month" : "Changes the money goal")
            .sheet(isPresented: $editing) {
                MoneyGoalSheet(goal: $goalAmount, spent: spent, lastMonth: lastMonth)
                    .presentationDetents([.medium, .large])
            }
    }
}

extension MoneyGoal.State {
    /// Green on pace, the accent when ahead of pace, red over the goal.
    var colour: Color {
        switch self {
        case .onPace: Theme.keyGreen
        case .ahead: Theme.accent
        case .over: Theme.candleUp
        }
    }
}
