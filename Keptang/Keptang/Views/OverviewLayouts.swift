import SwiftData
import SwiftUI

/// Everything Overview shows, worked out once, and what its controls do. Each style lays it out
/// its own way; the figures and the actions are the same in all of them.
struct OverviewData {
    @Binding var range: TimeRange
    @Binding var style: ChartStyle
    @Binding var showAverage: Bool
    @Binding var showPrevious: Bool
    @Binding var selectedDate: Date?

    let category: SpendCategory?
    let now: Date
    let earliest: Int
    let page: Int
    let interval: DateInterval
    let points: [SpendPoint]
    let previousPoints: [SpendPoint]
    let average: [Double]
    let total: Double
    let previous: Double
    /// Money in during the period shown, and all spending in it (whatever category is charted).
    let income: Double
    let spentAll: Double
    let comparisonName: String
    let selected: SpendPoint?
    /// "This month", or the dates of an earlier period.
    let periodName: String
    /// The dates, always: "October 2026".
    let periodLabel: String
    let watchlist: [WatchlistRow]
    let recent: [Receipt]
    let bucketReceipts: [Receipt]
    let goalSpent: Double
    let goalLastMonth: Double
    let goalMonth: DateInterval
    let highlight: ((Receipt) -> Bool)?
    let picker: PeriodPicker

    let move: (Int) -> Void
    let today: () -> Void
    let setCategory: (SpendCategory?) -> Void
    let scan: () -> Void
    let clearSelection: () -> Void

    var name: String { category?.name ?? "All spending" }
    /// The figure on show: the point under the crosshair, otherwise the period's total.
    var shown: Double { selected?.amount ?? total }
    var change: Double? { previous > 0 ? (total - previous) / previous : nil }
    var showsAverage: Bool { showAverage && style != .line && range != .day }

    var pager: PeriodPager {
        PeriodPager(label: periodLabel, canGoEarlier: page > earliest, canGoLater: page < 0,
                    onPage: move, onToday: today, picker: picker)
    }

    func chart(height: CGFloat) -> some View {
        SpendChart(points: points, previous: showPrevious ? previousPoints : [],
                   average: showsAverage ? average : [],
                   interval: interval, range: range, style: style,
                   selected: selected, selectedDate: $selectedDate, onPage: move)
            .frame(height: height)
            .accessibilityAction(named: "Earlier period") { move(-1) }
            .accessibilityAction(named: "Later period") { move(1) }
    }

    var legend: ChartLegend {
        ChartLegend(style: style, showAverage: showsAverage, averageName: range.averageName, showPrevious: showPrevious)
    }

    func goal<Label: View>(@ViewBuilder _ label: @escaping (MoneyGoal?) -> Label) -> GoalButton<Label> {
        GoalButton(spent: goalSpent, lastMonth: goalLastMonth, month: goalMonth, label: label)
    }

    /// "Tue 13 Oct", "13:00" or "Oct 2026".
    func shortTitle(_ date: Date) -> String {
        switch range {
        case .day: date.formatted(.dateTime.hour().minute())
        case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .year: date.formatted(.dateTime.month(.abbreviated).year())
        }
    }
}

// MARK: - Classic: a TradingView terminal

/// Edge-to-edge panels split by thin gaps: the symbol header with its price and change, one
/// toolbar of timeframes, chart types and indicators, the chart as the main pane, key stats for
/// the goal, and watchlist and receipt tables with real columns.
struct ClassicOverview: View {
    let d: OverviewData

    var body: some View {
        ScrollView {
            VStack(spacing: 6) {
                VStack(spacing: 0) {
                    symbolBar.panel()
                    Rectangle().fill(Theme.line).frame(height: 1)
                    toolbar
                    Rectangle().fill(Theme.line).frame(height: 1)
                    VStack(spacing: 4) {
                        d.pager
                        d.chart(height: 360)
                        d.legend.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 10)
                    .background(Theme.surface)
                }
                if let selected = d.selected {
                    table(title: "Details", note: d.range.bucketTitle(for: selected.date)) {
                        receiptRows(d.bucketReceipts, empty: "Nothing spent")
                        Button("Clear crosshair", action: d.clearSelection)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }
                }
                keyStats
                watchlist
                table(title: "Latest receipts", note: nil) {
                    if d.recent.isEmpty {
                        Button("Scan your first receipt", action: d.scan).buttonStyle(BlockButtonStyle(prominent: true)).padding(12)
                    } else {
                        receiptRows(d.recent, empty: "")
                    }
                }
            }
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
    }

    // Symbol, last price, change: the header of a TradingView chart.
    private var symbolBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(d.category?.color ?? Theme.accent)
                    Image(systemName: d.category?.symbol ?? "bahtsign")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(d.category == nil ? Theme.onAccent : Theme.onBright)
                }
                .frame(width: 24, height: 24)
                Text(d.name).font(.headline).foregroundStyle(Theme.ink)
                Text("THB · \(d.range.rawValue)").font(.subheadline).foregroundStyle(Theme.muted)
                Spacer(minLength: 4)
                if d.category != nil {
                    Button { d.setCategory(nil) } label: {
                        Label("All", systemImage: "xmark").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all spending")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(d.shown.baht)
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel(d.selected == nil ? "Total \(d.total.baht)" : "Selected \(d.shown.baht)")
                if let change = d.change {
                    let delta = d.total - d.previous
                    Text("\(delta >= 0 ? "+" : "−")\(abs(delta).bahtWhole) (\(delta >= 0 ? "+" : "−")\(abs(change).percent))")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                        .foregroundStyle(delta >= 0 ? Theme.up : Theme.down)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            // One line, always there, so the chart never moves when the crosshair comes out.
            Group {
                if let s = d.selected {
                    HStack(spacing: 10) {
                        Text(d.shortTitle(s.date)).foregroundStyle(Theme.ink)
                        stat("S", s.amount.bahtWhole)
                        if s.count > 1 { stat("H", s.high.bahtWhole); stat("L", s.low.bahtWhole) }
                        stat("N", "\(s.count)")
                    }
                } else {
                    Text("\(d.periodName) · vs \(d.comparisonName.isEmpty ? "previous \(d.range.longName)" : d.comparisonName)")
                        .foregroundStyle(Theme.muted)
                }
            }
            .font(.caption.monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity, alignment: .leading)
            if d.income > 0 { MoneyFlowStrip(income: d.income, spent: d.spentAll) }
        }
    }

    private func stat(_ key: String, _ value: String) -> some View {
        HStack(spacing: 3) {
            Text(key).foregroundStyle(Theme.muted)
            Text(value).foregroundStyle(Theme.accentText)
        }
    }

    // Timeframes, chart types and indicators in one strip.
    private var toolbar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                ForEach(TimeRange.allCases) { option in
                    toolButton(isOn: d.range == option, label: Text(option.rawValue).font(.subheadline.weight(.semibold))) {
                        d.range = option
                    }
                    .accessibilityLabel(option.longName)
                }
                Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 6)
                ForEach(ChartStyle.allCases) { option in
                    toolButton(isOn: d.style == option, label: Image(systemName: option.symbol).font(.subheadline)) {
                        d.style = option
                    }
                    .accessibilityLabel(option.name)
                }
                Rectangle().fill(Theme.line).frame(width: 1, height: 22).padding(.horizontal, 6)
                Menu {
                    Toggle(d.range.averageName, isOn: d.$showAverage)
                    Toggle("Previous period", isOn: d.$showPrevious)
                } label: {
                    Label("Indicators", systemImage: "function")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(d.showAverage || d.showPrevious ? Theme.accentText : Theme.ink)
                        .padding(.horizontal, 8)
                        .frame(minHeight: 44)
                }
            }
            .padding(.horizontal, 8)
        }
        .background(Theme.surface)
    }

    private func toolButton<L: View>(isOn: Bool, label: L, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            label
                .foregroundStyle(isOn ? Theme.accentText : Theme.ink)
                .frame(minWidth: 40, minHeight: 32)
                .background(RoundedRectangle(cornerRadius: 4).fill(isOn ? Theme.accent.opacity(0.14) : .clear))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    // The goal as key statistics: a thin bar and three figures.
    private var keyStats: some View {
        d.goal { goal in
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Monthly goal").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    Spacer()
                    if let goal {
                        Text(goal.fraction.percent).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(goal.state.colour)
                    } else {
                        Text("Set goal").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.accentText)
                    }
                }
                if let goal {
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Rectangle().fill(Theme.line)
                            Rectangle().fill(goal.state.colour).frame(width: proxy.size.width * min(goal.fraction, 1))
                        }
                    }
                    .frame(height: 6)
                    HStack(alignment: .top) {
                        if goal.state == .over {
                            keyStat("Over by", goal.overBy.bahtWhole, "\(goal.daysLeft) days to go", colour: Theme.up)
                        } else {
                            keyStat("Per day", goal.perDay.bahtWhole, "for \(goal.daysLeft) days")
                            keyStat("Left", goal.left.bahtWhole, nil)
                        }
                        keyStat("Spent", goal.spent.bahtWhole, "of \(goal.goal.bahtWhole)")
                    }
                }
            }
            .panel()
        }
    }

    private func keyStat(_ title: String, _ value: String, _ note: String?, colour: Color = Theme.ink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(Theme.muted)
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).foregroundStyle(colour)
                .lineLimit(1).minimumScaleFactor(0.6)
            if let note { Text(note).font(.caption).foregroundStyle(Theme.muted) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Symbol / Last / Chg / Chg% columns.
    private var watchlist: some View {
        table(title: "Watchlist", note: d.periodName) {
            HStack {
                Text("Symbol").frame(maxWidth: .infinity, alignment: .leading)
                Text("Last").frame(width: 76, alignment: .trailing)
                Text("Chg").frame(width: 64, alignment: .trailing)
                Text("Chg%").frame(width: 56, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(Theme.muted)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityHidden(true)
            if d.watchlist.isEmpty {
                Text("Nothing spent in this period.").foregroundStyle(Theme.muted).padding(12)
            }
            ForEach(d.watchlist) { row in
                let isOn = d.category == row.category
                let delta = row.amount - row.previous
                Button { d.setCategory(isOn ? nil : row.category) } label: {
                    HStack {
                        HStack(spacing: 8) {
                            Circle().fill(row.category.color).frame(width: 10, height: 10)
                            Text(row.category.name).font(.subheadline.weight(isOn ? .bold : .medium)).foregroundStyle(Theme.ink).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.amount.bahtWhole).frame(width: 76, alignment: .trailing).foregroundStyle(Theme.ink)
                        Text(row.previous > 0 ? "\(delta >= 0 ? "+" : "−")\(abs(delta).bahtCompact)" : "—")
                            .frame(width: 64, alignment: .trailing)
                            .foregroundStyle(row.previous > 0 ? (delta >= 0 ? Theme.up : Theme.down) : Theme.muted)
                        Text(row.change.map { "\($0 >= 0 ? "+" : "−")\(abs($0).percent)" } ?? "new")
                            .frame(width: 56, alignment: .trailing)
                            .foregroundStyle(row.change.map { $0 >= 0 ? Theme.up : Theme.down } ?? Theme.muted)
                    }
                    .font(.subheadline.monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 12)
                    .frame(minHeight: 44)
                    .background(isOn ? Theme.accent.opacity(0.12) : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityHint(isOn ? "Shows all spending again" : "Charts this category")
            }
        }
    }

    @ViewBuilder
    private func receiptRows(_ receipts: [Receipt], empty: String) -> some View {
        if receipts.isEmpty, !empty.isEmpty {
            Text(empty).foregroundStyle(Theme.muted).padding(12)
        }
        ForEach(receipts) { receipt in
            let hit = d.highlight?(receipt)
            NavigationLink { ReceiptDetailView(receipt: receipt) } label: {
                HStack(spacing: 10) {
                    Text(receipt.date, format: .dateTime.day().month(.abbreviated))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.muted)
                        .frame(width: 48, alignment: .leading)
                    Image(systemName: receipt.iconSymbol).font(.caption).foregroundStyle(Theme.muted).frame(width: 16)
                    Text(receipt.shopName).font(.subheadline).foregroundStyle(Theme.ink).lineLimit(1)
                    Spacer(minLength: 8)
                    Text(receipt.total.baht).font(.subheadline.monospacedDigit()).foregroundStyle(Theme.ink)
                }
                .padding(.horizontal, 12)
                .frame(minHeight: 44)
                .background(hit == true ? Theme.accent.opacity(0.1) : .clear)
                .opacity(hit == false ? 0.4 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }

    private func table<Content: View>(title: String, note: String?, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                    .accessibilityAddTraits(.isHeader)
                if let note { Text(note).font(.caption).foregroundStyle(Theme.muted).lineLimit(1) }
                Spacer()
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 40)
            Rectangle().fill(Theme.line).frame(height: 1)
            content()
        }
        .padding(.bottom, 6)
        .background(Theme.surface)
    }
}

private extension View {
    /// A classic pane: full width, padded, on the panel colour.
    func panel() -> some View {
        padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Theme.surface)
    }
}

// MARK: - Gruv: a text terminal

/// A shell session: a prompt, then boxed panes with their titles cut into the border, a text
/// progress bar, bracketed command tokens instead of keys, and aligned columns of log lines.
struct TerminalOverview: View {
    let d: OverviewData
    @State private var cursor = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                prompt
                TermBox(title: "goal") { goal }
                TermBox(title: d.name, trailing: d.periodName) { readout }
                TermBox(title: "controls") { controls }
                TermBox(title: "chart") {
                    d.pager
                    d.chart(height: 300)
                    d.legend
                }
                if let selected = d.selected {
                    TermBox(title: "grep \(d.shortTitle(selected.date))") {
                        logLines(d.bucketReceipts, empty: "(no receipts)")
                        token("[x] clear", isOn: false, action: d.clearSelection)
                    }
                }
                TermBox(title: "ls categories") { categories }
                TermBox(title: "tail -5 receipts") {
                    if d.recent.isEmpty {
                        token("$ scan --first", isOn: true, action: d.scan)
                    } else {
                        logLines(d.recent, empty: "")
                    }
                }
            }
            .font(.system(.footnote, design: .monospaced))
            .padding(12)
            .frame(maxWidth: 1000)
            .frame(maxWidth: .infinity)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 0.6).repeatForever()) { cursor = false }
        }
    }

    private var prompt: some View {
        HStack(spacing: 0) {
            Text("you").foregroundStyle(Theme.down)
            Text("@snapceipt").foregroundStyle(Theme.ink)
            Text(":~/overview").foregroundStyle(Theme.accentText)
            Text("$ ").foregroundStyle(Theme.ink)
            Text("watch --range \(d.range.rawValue.lowercased())").foregroundStyle(Theme.muted)
            Rectangle().fill(Theme.accent).frame(width: 8, height: 15).opacity(cursor ? 1 : 0.1).padding(.leading, 2)
        }
        .font(.system(.footnote, design: .monospaced, weight: .semibold))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .accessibilityHidden(true)
    }

    // [████████░░░░░░░░░░░░] 44.8%
    private var goal: some View {
        d.goal { goal in
            VStack(alignment: .leading, spacing: 4) {
                if let goal {
                    let cells = 22
                    let filled = Int((min(goal.fraction, 1) * Double(cells)).rounded())
                    HStack(spacing: 0) {
                        Text("[").foregroundStyle(Theme.muted)
                        Text(String(repeating: "█", count: filled)).foregroundStyle(goal.state.colour)
                        Text(String(repeating: "░", count: cells - filled)).foregroundStyle(Theme.quiet)
                        Text("] ").foregroundStyle(Theme.muted)
                        Text(goal.fraction.percent).foregroundStyle(goal.state.colour).fontWeight(.bold)
                    }
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    if goal.state == .over {
                        kv("over_by", goal.overBy.bahtWhole, colour: Theme.up)
                        kv("to_go", "\(goal.daysLeft)d")
                    } else {
                        kv("per_day", "\(goal.perDay.bahtWhole) × \(goal.daysLeft)d", bold: true)
                        kv("left", goal.left.bahtWhole, bold: true)
                    }
                    kv("spent", "\(goal.spent.bahtWhole) / \(goal.goal.bahtWhole)")
                } else {
                    Text("$ goal --set   # tap to set a money goal").foregroundStyle(Theme.accentText)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func kv(_ key: String, _ value: String, colour: Color = Theme.ink, bold: Bool = false) -> some View {
        HStack(spacing: 0) {
            Text(key.uppercased()).foregroundStyle(Theme.muted).frame(width: 92, alignment: .leading)
            Text(value).foregroundStyle(colour).fontWeight(bold ? .bold : .regular)
        }
        .font(.system(bold ? .subheadline : .footnote, design: .monospaced))
        .lineLimit(1)
        .minimumScaleFactor(0.6)
    }

    private var readout: some View {
        VStack(alignment: .leading, spacing: 6) {
            if d.category != nil {
                token("[x] all spending", isOn: false) { d.setCategory(nil) }
            }
            Text(d.shown.baht)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            if let change = d.change {
                Text("Δ \(change >= 0 ? "+" : "−")\(abs(change).percent) vs \(d.comparisonName)")
                    .foregroundStyle(change >= 0 ? Theme.up : Theme.down)
            } else {
                Text("Δ n/a").foregroundStyle(Theme.muted)
            }
            if d.income > 0 {
                let net = d.income - d.spentAll
                Text("IN +\(d.income.bahtWhole)  OUT \(d.spentAll.bahtWhole)  NET \(net >= 0 ? "+" : "−")\(abs(net).bahtWhole)")
                    .foregroundStyle(net >= 0 ? Theme.down : Theme.up)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Group {
                if let s = d.selected {
                    Text("> \(d.shortTitle(s.date).uppercased())  SPENT \(s.amount.bahtWhole)\(s.count > 1 ? "  HI \(s.high.bahtWhole)  LO \(s.low.bahtWhole)" : "")  N=\(s.count)")
                        .foregroundStyle(Theme.accentText)
                } else {
                    Text("> touch the chart for details").foregroundStyle(Theme.muted)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.5)
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            row("range") {
                ForEach(TimeRange.allCases) { option in
                    token(option.rawValue, isOn: d.range == option) { d.range = option }
                        .accessibilityLabel(option.longName)
                }
            }
            row("chart") {
                ForEach(ChartStyle.allCases) { option in
                    token(option.rawValue.uppercased(), isOn: d.style == option) { d.style = option }
                }
            }
            row("fx") {
                token("\(d.showAverage ? "[x]" : "[ ]") AVG", isOn: false) { d.showAverage.toggle() }
                    .accessibilityLabel(d.range.averageName)
                    .accessibilityValue(d.showAverage ? "On" : "Off")
                token("\(d.showPrevious ? "[x]" : "[ ]") PREV", isOn: false) { d.showPrevious.toggle() }
                    .accessibilityLabel("Previous period")
                    .accessibilityValue(d.showPrevious ? "On" : "Off")
            }
        }
    }

    private func row<Content: View>(_ key: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 4) {
            Text(key.uppercased()).foregroundStyle(Theme.muted).frame(width: 56, alignment: .leading).accessibilityHidden(true)
            content()
        }
    }

    /// A bracketed command word; the chosen one is printed in reverse video.
    private func token(_ text: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            KeyClick.play()
            action()
        } label: {
            Text(text)
                .font(.system(.footnote, design: .monospaced, weight: .bold))
                .foregroundStyle(isOn ? Theme.paper : Theme.ink)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isOn ? Theme.ink : Color.clear)
                .overlay(Rectangle().strokeBorder(isOn ? Theme.ink : Theme.line, lineWidth: 1))
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var categories: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Text("NAME").frame(maxWidth: .infinity, alignment: .leading)
                Text("AMOUNT").frame(width: 84, alignment: .trailing)
                Text("CHG").frame(width: 64, alignment: .trailing)
            }
            .foregroundStyle(Theme.muted)
            .accessibilityHidden(true)
            if d.watchlist.isEmpty { Text("(empty)").foregroundStyle(Theme.muted).padding(.vertical, 8) }
            ForEach(d.watchlist) { row in
                let isOn = d.category == row.category
                Button { d.setCategory(isOn ? nil : row.category) } label: {
                    HStack(spacing: 0) {
                        HStack(spacing: 6) {
                            Rectangle().fill(row.category.color).frame(width: 8, height: 12)
                            Text(row.category.name.lowercased()).lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Text(row.amount.bahtWhole).frame(width: 84, alignment: .trailing)
                        Text(row.change.map { "\($0 >= 0 ? "▲" : "▼")\(abs($0).percent)" } ?? "new")
                            .frame(width: 64, alignment: .trailing)
                            .foregroundStyle(isOn ? Theme.paper : row.change.map { $0 >= 0 ? Theme.up : Theme.down } ?? Theme.muted)
                    }
                    .foregroundStyle(isOn ? Theme.paper : Theme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 4)
                    .frame(minHeight: 40)
                    .background(isOn ? Theme.ink : .clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityHint(isOn ? "Shows all spending again" : "Charts this category")
            }
        }
    }

    @ViewBuilder
    private func logLines(_ receipts: [Receipt], empty: String) -> some View {
        if receipts.isEmpty, !empty.isEmpty { Text(empty).foregroundStyle(Theme.muted) }
        ForEach(receipts) { receipt in
            let hit = d.highlight?(receipt)
            NavigationLink { ReceiptDetailView(receipt: receipt) } label: {
                HStack(spacing: 8) {
                    Text(receipt.date, format: .dateTime.month(.twoDigits).day(.twoDigits).hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                        .foregroundStyle(Theme.muted)
                    Text(receipt.shopName).foregroundStyle(hit == true ? Theme.accentText : Theme.ink).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(receipt.total.baht).foregroundStyle(Theme.ink)
                }
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minHeight: 40)
                .opacity(hit == false ? 0.4 : 1)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
        }
    }
}

/// A terminal pane: a thick square border with its title cut into the top edge.
struct TermBox<Content: View>: View {
    let title: String
    var trailing: String? = nil
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) { content }
            .padding(12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface)
            .overlay(Rectangle().strokeBorder(Theme.line, lineWidth: 2))
            .overlay(alignment: .topLeading) {
                HStack(spacing: 6) {
                    Text(" \(title.uppercased()) ").foregroundStyle(Theme.accentText)
                    if let trailing { Text("\(trailing.lowercased()) ").foregroundStyle(Theme.muted) }
                }
                .font(.system(.caption, design: .monospaced, weight: .bold))
                .lineLimit(1)
                .background(Theme.paper)
                .offset(x: 10, y: -8)
                .accessibilityAddTraits(.isHeader)
            }
    }
}

// MARK: - Kawaii: a friendly card app

/// A greeting and the big number, the goal as a fat pill with a little face riding along it, pill
/// chips for the controls, the chart in a soft card, categories as round bubbles and receipts as
/// cards.
struct KawaiiOverview: View {
    let d: OverviewData

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                greeting
                goalCard
                controls
                KawaiiCard {
                    d.pager
                    d.chart(height: 280)
                    d.legend
                }
                if let selected = d.selected {
                    KawaiiCard {
                        HStack {
                            Text("\(d.shortTitle(selected.date).lowercased()) ✿").font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
                            Spacer()
                            Button("close", action: d.clearSelection)
                                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                                .foregroundStyle(Theme.accentText)
                                .frame(minHeight: 44)
                        }
                        if d.bucketReceipts.isEmpty {
                            Text("nothing spent here ♡").foregroundStyle(Theme.muted)
                        }
                        ForEach(d.bucketReceipts) { receiptCard($0, flat: true) }
                    }
                }
                bubbles
                VStack(alignment: .leading, spacing: 10) {
                    heading("latest receipts")
                    if d.recent.isEmpty {
                        Button("scan your first receipt ♡", action: d.scan).buttonStyle(BlockButtonStyle(prominent: true))
                    }
                    ForEach(d.recent) { receiptCard($0, flat: false) }
                }
            }
            .font(.system(.body, design: .rounded))
            .padding(16)
            .frame(maxWidth: 900)
            .frame(maxWidth: .infinity)
        }
    }

    private var hello: String {
        switch Calendar.app.component(.hour, from: d.now) {
        case 5..<12: "good morning"
        case 12..<18: "good afternoon"
        default: "good evening"
        }
    }

    private var greeting: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(hello) ♡").font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Theme.accentText)
                Spacer()
                if let category = d.category {
                    Button { d.setCategory(nil) } label: {
                        Label(category.name.lowercased(), systemImage: "xmark.circle.fill")
                            .font(.system(.footnote, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.onBright)
                            .padding(.horizontal, 12)
                            .frame(minHeight: 34)
                            .background(category.color, in: Capsule())
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Show all spending")
                }
            }
            Text(d.selected == nil ? "you've spent" : "on this \(d.range == .year ? "month" : d.range == .day ? "hour" : "day")")
                .font(.system(.title3, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text(d.shown.baht)
                .font(.system(size: 44, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(Theme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            HStack(spacing: 8) {
                Text(d.periodName.lowercased()).font(.system(.subheadline, design: .rounded)).foregroundStyle(Theme.muted)
                if let change = d.change {
                    Text("\(change >= 0 ? "▲" : "▼") \(abs(change).percent) vs \(d.comparisonName)")
                        .font(.system(.caption, design: .rounded, weight: .bold))
                        .foregroundStyle(change >= 0 ? Theme.up : Theme.down)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background((change >= 0 ? Theme.up : Theme.down).opacity(0.12), in: Capsule())
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
            if d.income > 0 {
                let net = d.income - d.spentAll
                HStack(spacing: 8) {
                    chip("came in +\(d.income.bahtWhole)", tint: Theme.keyGreen)
                    chip("\(net >= 0 ? "saved" : "short") \(abs(net).bahtWhole)", tint: net >= 0 ? Theme.keyGreen : Theme.up)
                }
            }
            // Always one line, so nothing jumps when the chart is touched.
            Group {
                if let s = d.selected {
                    Text("\(d.shortTitle(s.date).lowercased()) · \(s.count) receipt\(s.count == 1 ? "" : "s")")
                } else {
                    Text("tap the chart to peek at a day ✿")
                }
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.muted)
            .lineLimit(1)
        }
        .padding(.horizontal, 4)
    }

    private var goalCard: some View {
        d.goal { goal in
            KawaiiCard {
                HStack {
                    heading("my goal")
                    Spacer()
                    if let goal {
                        Text(goal.fraction.percent).font(.system(.headline, design: .rounded)).foregroundStyle(goal.state.colour)
                    }
                }
                if let goal {
                    GeometryReader { proxy in
                        let fill = max(proxy.size.width * min(goal.fraction, 1), 34)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Theme.accent.opacity(0.14))
                            Capsule().fill(goal.state.colour.opacity(0.85)).frame(width: fill)
                            Text(face(goal.state))
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(Theme.ink)
                                .padding(.horizontal, 6)
                                .frame(height: 26)
                                .background(Theme.surface, in: Capsule())
                                .overlay(Capsule().strokeBorder(goal.state.colour, lineWidth: 2))
                                .fixedSize()
                                .offset(x: max(0, min(fill - 62, proxy.size.width - 66)))
                        }
                    }
                    .frame(height: 34)
                    Text(message(goal.state)).font(.system(.subheadline, design: .rounded, weight: .semibold)).foregroundStyle(Theme.ink)
                    HStack(spacing: 8) {
                        if goal.state == .over {
                            chip("over by \(goal.overBy.bahtWhole)", tint: Theme.up)
                        } else {
                            chip("\(goal.perDay.bahtWhole) a day · \(goal.daysLeft) days", tint: Theme.accent)
                            chip("\(goal.left.bahtWhole) left", tint: Theme.keyGreen)
                        }
                    }
                    Text("\(goal.spent.bahtWhole) of \(goal.goal.bahtWhole)").font(.system(.caption, design: .rounded)).foregroundStyle(Theme.muted)
                } else {
                    Text("set a monthly goal and i'll cheer you on (◕‿◕)").foregroundStyle(Theme.muted)
                }
            }
        }
    }

    private func face(_ state: MoneyGoal.State) -> String {
        switch state {
        case .onPace: "(◕‿◕)"
        case .ahead: "(・_・;)"
        case .over: "(╥﹏╥)"
        }
    }

    private func message(_ state: MoneyGoal.State) -> String {
        switch state {
        case .onPace: "you're doing great! keep it up ♡"
        case .ahead: "a little fast this month, slow down a bit"
        case .over: "over the goal, let's be gentle next month"
        }
    }

    private func chip(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.footnote, design: .rounded, weight: .bold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(tint.opacity(0.18), in: Capsule())
            .lineLimit(1)
            .minimumScaleFactor(0.7)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(TimeRange.allCases) { option in
                        pill(option == .day ? "day" : option == .week ? "week" : option == .month ? "month" : "year",
                             symbol: nil, isOn: d.range == option) { d.range = option }
                    }
                }
                .padding(.vertical, 2)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ChartStyle.allCases) { option in
                        pill(option.name.lowercased(), symbol: option.symbol, isOn: d.style == option) { d.style = option }
                    }
                    pill("average", symbol: "sparkles", isOn: d.showAverage) { d.showAverage.toggle() }
                    pill("last time", symbol: "clock.arrow.circlepath", isOn: d.showPrevious) { d.showPrevious.toggle() }
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func pill(_ title: String, symbol: String?, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button {
            KeyClick.play()
            action()
        } label: {
            HStack(spacing: 5) {
                if let symbol { Image(systemName: symbol).font(.footnote.weight(.bold)) }
                Text(title).font(.system(.subheadline, design: .rounded, weight: .bold))
            }
            .foregroundStyle(isOn ? Theme.onAccent : Theme.ink)
            .padding(.horizontal, 16)
            .frame(minHeight: 40)
            .background(isOn ? Theme.accent : Theme.surface, in: Capsule())
            .shadow(color: Theme.ink.opacity(isOn ? 0 : 0.07), radius: 6, y: 2)
            .frame(minHeight: 44)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var bubbles: some View {
        VStack(alignment: .leading, spacing: 10) {
            heading("where it went")
            if d.watchlist.isEmpty {
                Text("nothing spent yet ♡").foregroundStyle(Theme.muted)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(d.watchlist) { row in
                        let isOn = d.category == row.category
                        Button { d.setCategory(isOn ? nil : row.category) } label: {
                            VStack(spacing: 6) {
                                Image(systemName: row.category.symbol)
                                    .font(.system(size: 22, weight: .bold))
                                    .foregroundStyle(Theme.onBright)
                                    .frame(width: 62, height: 62)
                                    .background(row.category.color, in: Circle())
                                    .overlay(Circle().strokeBorder(isOn ? Theme.accent : .clear, lineWidth: 3).padding(-4))
                                Text(row.category.name.lowercased())
                                    .font(.system(.caption, design: .rounded, weight: .semibold))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                Text(row.amount.bahtCompact)
                                    .font(.system(.caption, design: .rounded))
                                    .foregroundStyle(Theme.muted)
                            }
                            .frame(width: 80)
                            .opacity(d.category == nil || isOn ? 1 : 0.5)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityElement(children: .combine)
                        .accessibilityAddTraits(isOn ? .isSelected : [])
                        .accessibilityHint(isOn ? "Shows all spending again" : "Charts this category")
                    }
                }
                .padding(6)
            }
        }
    }

    private func receiptCard(_ receipt: Receipt, flat: Bool) -> some View {
        let hit = d.highlight?(receipt)
        return NavigationLink { ReceiptDetailView(receipt: receipt) } label: {
            HStack(spacing: 12) {
                Image(systemName: receipt.iconSymbol)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(Theme.onBright)
                    .frame(width: 44, height: 44)
                    .background(receipt.iconColor, in: Circle())
                VStack(alignment: .leading, spacing: 2) {
                    Text(receipt.shopName).font(.system(.body, design: .rounded, weight: .bold)).foregroundStyle(Theme.ink).lineLimit(1)
                    Text(receipt.date, format: .dateTime.day().month(.abbreviated).hour().minute())
                        .font(.system(.caption, design: .rounded)).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 8)
                Text(receipt.total.baht).font(.system(.headline, design: .rounded).monospacedDigit()).foregroundStyle(Theme.ink)
            }
            .padding(flat ? 6 : 14)
            .background(flat ? Color.clear : Theme.surface, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(hit == true ? Theme.accent : .clear, lineWidth: 2))
            .shadow(color: Theme.ink.opacity(flat ? 0 : 0.06), radius: 10, y: 4)
            .opacity(hit == false ? 0.4 : 1)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
    }

    private func heading(_ text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "heart.fill").font(.caption).foregroundStyle(Theme.accent)
            Text(text).font(.system(.headline, design: .rounded)).foregroundStyle(Theme.ink)
        }
        .accessibilityAddTraits(.isHeader)
    }
}

/// Money in, money out and what's left, for the period on show.
struct MoneyFlowStrip: View {
    let income: Double
    let spent: Double

    var body: some View {
        let net = income - spent
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 12) { parts(net) }
            VStack(alignment: .leading, spacing: 2) { parts(net) }
        }
        .font(Theme.figure(.footnote))
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func parts(_ net: Double) -> some View {
        part("in", "+\(income.bahtWhole)", Theme.down)
        part("out", spent.bahtWhole, Theme.ink)
        part("net", "\(net >= 0 ? "+" : "−")\(abs(net).bahtWhole)", net >= 0 ? Theme.down : Theme.up)
    }

    private func part(_ name: String, _ value: String, _ colour: Color) -> some View {
        HStack(spacing: 4) {
            Text(Theme.cased(name)).foregroundStyle(Theme.muted)
            Text(value).foregroundStyle(colour).fontWeight(.semibold)
        }
    }
}

/// A soft white card with big round corners and a gentle shadow, no border.
struct KawaiiCard<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .shadow(color: Theme.ink.opacity(0.07), radius: 14, y: 6)
    }
}
