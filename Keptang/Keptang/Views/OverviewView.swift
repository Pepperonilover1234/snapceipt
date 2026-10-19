import Charts
import SwiftData
import SwiftUI

enum ChartStyle: String, CaseIterable, Identifiable {
    case line, bars, candles

    var id: String { rawValue }

    var name: String {
        switch self {
        case .line: "Line"
        case .bars: "Bars"
        case .candles: "Candles"
        }
    }

    var symbol: String {
        switch self {
        case .line: "chart.xyaxis.line"
        case .bars: "chart.bar.fill"
        case .candles: "chart.bar.xaxis"
        }
    }
}

/// The home screen, laid out like a TradingView chart: a ticker header, the timeframe and chart-type
/// strip, a tall chart with a crosshair over a volume pane (receipts per bucket), then a watchlist of
/// categories. Tapping a category charts just that category.
struct OverviewView: View {
    @Binding var tab: AppTab
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    /// Money in, kept apart from spending.
    @Query(filter: #Predicate<Receipt> { $0.isIncome == true }, sort: \Receipt.date) private var incomes: [Receipt]
    @State private var range: TimeRange = LaunchOption.string("range").flatMap(TimeRange.init(rawValue:)) ?? .month
    @State private var style: ChartStyle = LaunchOption.string("chart").flatMap(ChartStyle.init(rawValue:)) ?? .line
    /// 0 is the period ending now; −1 the one before it, and so on.
    @State private var offset = -(Int(LaunchOption.string("back") ?? "") ?? 0)
    @State private var selectedDate: Date?
    /// The category being charted; nil for all spending.
    @State private var category: SpendCategory? = LaunchOption.string("category").flatMap(SpendCategory.init(rawValue:))
    /// The receipt type whose receipts are listed (the chart doesn't change).
    @AppStorage("chartAverage") private var showAverage = true
    @AppStorage("chartPrevious") private var showPrevious = false
    @State private var showingAbout = ["settings", "chatbots"].contains(LaunchOption.string("sheet") ?? "")
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var cardColumns: [GridItem] {
        let column = GridItem(.flexible(), spacing: 12, alignment: .top)
        return sizeClass == .regular ? [column, column] : [column]
    }

    var body: some View {
        let d = makeData()
        Group {
            switch Skin.current {
            case .console: consoleLayout(d)
            case .classic: ClassicOverview(d: d)
            case .gruv: TerminalOverview(d: d)
            case .kawaii: KawaiiOverview(d: d)
            }
        }
        .background(Theme.paper)
        .navigationTitle(Skin.current.appTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarLeading) {
                Button { showingAbout = true } label: { Label("Settings", systemImage: "gearshape") }
                AppearanceMenu()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button { tab = .scan } label: { Label("Add", systemImage: "plus") }
            }
        }
        .sheet(isPresented: $showingAbout) { AboutView() }
        .onChange(of: range) {
            selectedDate = nil
            offset = 0
        }
        .onAppear {
            if let raw = LaunchOption.string("goal"), let goal = Double(raw) {
                UserDefaults.standard.set(goal, forKey: "moneyGoal")
            }
            if let raw = LaunchOption.string("select"), let hours = Double(raw) {
                selectedDate = range.interval(offset: offset, now: .now).start.addingTimeInterval(hours * 3600)
            }
        }
    }

    /// Everything a layout shows, worked out once per redraw, and what it can do.
    private func makeData() -> OverviewData {
        let all = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let analyzer = category.map(all.only) ?? all
        let now = Date.now
        let earliest = all.earliestOffset(for: range, now: now)
        let page = min(0, max(offset, earliest))
        let interval = range.interval(offset: page, now: now)
        let points = analyzer.points(for: range, now: now, offset: page)
        let previousPoints = analyzer.points(for: range, now: now, offset: page - 1)
        let comparison = range.comparison(offset: page, now: now)
        let selected = selectedDate.flatMap { date in points.last { $0.date <= date } }
        let month = all.month(containing: now)
        let lastMonth = all.month(containing: Calendar.app.date(byAdding: .month, value: -1, to: month.start)!)
        return OverviewData(
            range: $range, style: $style, showAverage: $showAverage, showPrevious: $showPrevious, selectedDate: $selectedDate,
            category: category, now: now, earliest: earliest, page: page, interval: interval,
            points: points, previousPoints: previousPoints,
            average: SpendingAnalyzer.movingAverage(of: points, previous: previousPoints, window: range.averageWindow),
            total: analyzer.total(in: interval), previous: analyzer.total(in: comparison),
            income: incomes.filter { $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.total },
            spentAll: all.total(in: interval),
            comparisonName: range.comparisonLabel(comparison),
            selected: selected,
            periodName: page == 0 ? range.currentName : range.label(for: interval),
            periodLabel: range.label(for: interval),
            watchlist: watchlist(all: all, page: page, now: now),
            recent: Array(receipts.suffix(5).reversed()),
            bucketReceipts: selected.map { bucketReceipts(analyzer: analyzer, start: $0.date) } ?? [],
            goalSpent: all.total(in: month), goalLastMonth: all.total(in: lastMonth), goalMonth: month,
            highlight: highlightTest,
            picker: PeriodPicker(
                rules: PeriodPicking(range: range, now: now, firstReceipt: receipts.first?.date),
                showing: interval,
                receiptDays: Set(analyzer.receipts.map { Calendar.app.startOfDay(for: $0.date) }),
                onPick: { picked in
                    let target = PeriodPicking(range: range, now: .now, firstReceipt: receipts.first?.date).offset(for: picked)
                    setOffset(min(0, max(earliest, target)))
                }
            ),
            move: { move(by: $0, earliest: earliest) },
            today: { setOffset(0) },
            setCategory: { setCategory($0) },
            scan: { tab = .scan },
            clearSelection: { selectedDate = nil }
        )
    }

    /// The hardware layout: pinned goal bar, LCD header, knob and keys, the chart, then the cards.
    @ViewBuilder
    private func consoleLayout(_ d: OverviewData) -> some View {
        let all = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let analyzer = category.map(all.only) ?? all
        let now = d.now
        let earliest = d.earliest
        let page = d.page
        let interval = d.interval
        let points = d.points
        let previousPoints = d.previousPoints
        let total = d.total
        let previous = d.previous
        let comparison = range.comparison(offset: page, now: now)
        let selected = d.selected
        let periodName = d.periodName
        let average = d.average
        ScrollView {
            VStack(alignment: .leading, spacing: Skin.current.pageSpacing) {
                // The money goal on top, joined to the total below it.
                VStack(alignment: .leading, spacing: 12) {
                    if typeSize.isAccessibilitySize {
                        goalBar(all, now: now)
                        Rectangle().fill(Theme.line).frame(height: 1).padding(.horizontal, -14)
                    }
                    TickerHeader(
                        name: category?.name ?? "All spending",
                        category: category,
                        periodName: periodName,
                        total: total,
                        previous: previous,
                        comparisonName: range.comparisonLabel(comparison),
                        range: range,
                        selected: selected,
                        onClearCategory: { setCategory(nil) },
                        isFiltered: category != nil
                    )
                    if d.income > 0 { MoneyFlowStrip(income: d.income, spent: d.spentAll) }
                }
                .padding(Skin.current.panelPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .block()

                ChartToolbar(range: $range, style: $style, showAverage: $showAverage, showPrevious: $showPrevious,
                             averageName: range.averageName)

                VStack(spacing: 0) {
                    PeriodPager(
                        label: range.label(for: interval),
                        canGoEarlier: page > earliest,
                        canGoLater: page < 0,
                        onPage: { move(by: $0, earliest: earliest) },
                        onToday: { setOffset(0) },
                        picker: PeriodPicker(
                            rules: PeriodPicking(range: range, now: now, firstReceipt: receipts.first?.date),
                            showing: interval,
                            receiptDays: Set(analyzer.receipts.map { Calendar.app.startOfDay(for: $0.date) }),
                            onPick: { picked in
                                let target = PeriodPicking(range: range, now: .now, firstReceipt: receipts.first?.date).offset(for: picked)
                                setOffset(min(0, max(earliest, target)))
                            }
                        )
                    )
                    .padding(.horizontal, 8)
                    .padding(.top, 6)

                    SpendChart(points: points, previous: showPrevious ? previousPoints : [],
                               average: showAverage && style != .line && range != .day ? average : [],
                               interval: interval, range: range, style: style,
                               selected: selected, selectedDate: $selectedDate,
                               onPage: { move(by: $0, earliest: earliest) })
                        .frame(height: sizeClass == .regular ? 420 : 330)
                        .padding(.horizontal, 8)
                        .accessibilityAction(named: "Earlier period") { move(by: -1, earliest: earliest) }
                        .accessibilityAction(named: "Later period") { move(by: 1, earliest: earliest) }

                    ChartLegend(style: style, showAverage: showAverage && style != .line && range != .day,
                                averageName: range.averageName, showPrevious: showPrevious)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 10)
                }
                .background { DotGrid().padding(1).clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)) }
                .block()

                if let selected {
                    BucketReceiptsCard(
                        title: range.bucketTitle(for: selected.date),
                        receipts: bucketReceipts(analyzer: analyzer, start: selected.date),
                        onClear: { selectedDate = nil }
                    )
                }

                LazyVGrid(columns: cardColumns, alignment: .leading, spacing: Skin.current.pageSpacing) {
                    WatchlistCard(rows: watchlist(all: all, page: page, now: now), periodName: periodName,
                                  selected: category, onSelect: { setCategory($0) })
                    RecentReceiptsCard(receipts: Array(receipts.suffix(5).reversed()), onScan: { tab = .scan },
                                       matches: highlightTest)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 1200)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            // The money goal stays pinned at the very top, except at the largest text sizes.
            if !typeSize.isAccessibilitySize { goalBar(all, now: now) }
        }
    }

    /// The money goal, always about all spending this calendar month.
    private func goalBar(_ all: SpendingAnalyzer, now: Date) -> some View {
        let month = all.month(containing: now)
        let lastMonth = all.month(containing: Calendar.app.date(byAdding: .month, value: -1, to: month.start)!)
        return MoneyGoalBar(spent: all.total(in: month), lastMonth: all.total(in: lastMonth), month: month,
                            tracksAllWhileFiltered: category != nil, embedded: false)
    }

    private func move(by step: Int, earliest: Int) {
        setOffset(min(0, max(earliest, offset + step)))
    }

    private func setOffset(_ value: Int) {
        guard value != offset else { return }
        selectedDate = nil
        if reduceMotion { offset = value } else { withAnimation(.snappy) { offset = value } }
    }

    private func setCategory(_ value: SpendCategory?) {
        selectedDate = nil
        let change = { category = value }
        if reduceMotion { change() } else { withAnimation(.snappy, change) }
    }

    /// Which receipts match the active category or type, for highlighting; nil when nothing is picked.
    private var highlightTest: ((Receipt) -> Bool)? {
        if let category { return { receipt in receipt.items.contains { $0.category == category } || (category == .utilities && receipt.kind.isBill) } }
        return nil
    }


    /// The saved receipts in one chart bucket, newest first, found through the analyzer so they
    /// match the bucket's total exactly.
    private func bucketReceipts(analyzer: SpendingAnalyzer, start: Date) -> [Receipt] {
        let byID = Dictionary(receipts.map { ($0.persistentModelID, $0) }, uniquingKeysWith: { first, _ in first })
        return analyzer.receipts(in: range.bucket(startingAt: start))
            .compactMap { $0.id.flatMap { byID[$0] } }
            .reversed()
    }

    private func watchlist(all: SpendingAnalyzer, page: Int, now: Date) -> [WatchlistRow] {
        let interval = range.interval(offset: page, now: now)
        let before = range.comparison(offset: page, now: now)
        let current = Dictionary(uniqueKeysWithValues: all.categoryTotals(in: interval).map { ($0.category, $0.amount) })
        let previous = Dictionary(uniqueKeysWithValues: all.categoryTotals(in: before).map { ($0.category, $0.amount) })
        let total = current.values.reduce(0, +)
        return Set(current.keys).union(previous.keys)
            .map { category in
                WatchlistRow(category: category, amount: current[category] ?? 0, previous: previous[category] ?? 0,
                             share: total > 0 ? (current[category] ?? 0) / total : 0,
                             spark: all.only(category).points(for: range, now: now, offset: page).map(\.amount))
            }
            .filter { $0.amount > 0 || $0.previous > 0 }
            .sorted { ($0.amount, $0.previous) > ($1.amount, $1.previous) }
    }
}

extension TimeRange {
    /// Each range has its own colour (kept for older callers).
    var color: Color { Theme.accent }

    /// Buckets in the moving average: a week of days, or a quarter of months.
    var averageWindow: Int {
        switch self {
        case .day: 3
        case .week, .month: 7
        case .year: 3
        }
    }

    var averageName: String {
        switch self {
        case .day: "3-hour average"
        case .week, .month: "7-day average"
        case .year: "3-month average"
        }
    }

    /// The exact span one chart bucket covers: "Fri 17 Oct, 13:00–14:00", "Friday 17 October", "October 2026".
    func bucketTitle(for start: Date) -> String {
        let bucket = bucket(startingAt: start)
        switch self {
        case .day:
            let day = start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return "\(day), \(start.formatted(.dateTime.hour().minute()))–\(bucket.end.formatted(.dateTime.hour().minute()))"
        case .week, .month:
            return start.formatted(.dateTime.weekday(.wide).day().month(.wide).year())
        case .year:
            return start.formatted(.dateTime.month(.wide).year())
        }
    }
}

// MARK: - Header and toolbar

/// The symbol, the big figure and the change, like a ticker. With a point under the crosshair it adds
/// that point's figures in one row, the way TradingView shows open, high, low and close.
struct TickerHeader: View {
    let name: String
    let category: SpendCategory?
    let periodName: String
    let total: Double
    let previous: Double
    var comparisonName = ""
    let range: TimeRange
    let selected: SpendPoint?
    let onClearCategory: () -> Void
    var isFiltered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AdaptiveStack(spacing: 8) {
                HStack(spacing: 8) {
                    if let category {
                        CategoryIcon(symbol: category.symbol, size: 22, fill: category.color)
                    }
                    Text(Theme.cased(name)).font(.system(.title3, design: Skin.current.design, weight: .bold)).tracking(Theme.tracking * 0.4).foregroundStyle(Theme.ink)
                    Text("· \(periodName)").font(.system(.footnote, design: Skin.current.design)).foregroundStyle(Theme.muted)
                }
                if isFiltered {
                    Button(action: onClearCategory) {
                        Label("All spending", systemImage: "xmark.circle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint("Shows all spending again")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                // The LCD shows the point under the crosshair while there is one, otherwise the total.
                // Sized by the period total (no bucket is bigger), so the readout keeps its size
                // and nothing below it moves while the crosshair is out.
                ViewThatFits(in: .horizontal) {
                    lcd(pitch: 5.6, whole: false)
                    lcd(pitch: 4.4, whole: false)
                    lcd(pitch: 3.4, whole: false)
                    lcd(pitch: 3, whole: true)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                .accessibilityLabel(selected == nil ? "Total" : "Selected")
                .accessibilityValue((selected?.amount ?? total).baht)
                ChangeLabel(total: total, previous: previous, range: range, comparisonName: comparisonName)
            }
            .animation(reduceMotion ? nil : .snappy, value: total)

            // Always one line, so the chart below never moves when the crosshair comes and goes.
            Group {
                if let selected {
                    HStack(spacing: 12) { stats(selected) }
                        .accessibilityElement(children: .combine)
                } else {
                    Text("touch the chart for details")
                        .foregroundStyle(Theme.muted)
                        .accessibilityHidden(true)
                }
            }
            .font(Theme.figure(.footnote))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func lcd(pitch: CGFloat, whole: Bool) -> some View {
        let shown = selected?.amount ?? total
        if Theme.hardware {
            dots(pitch: pitch, whole: whole, shown: shown)
        } else {
            // Themes without the hardware look show the figure in plain type, sized like the dots.
            ZStack(alignment: .leading) {
                Text(whole ? total.bahtWhole : total.baht).hidden()
                Text(whole ? shown.bahtWhole : shown.baht).foregroundStyle(Theme.ink)
            }
            .font(.system(size: pitch * 7.4, weight: .semibold, design: Skin.current.figureDesign).monospacedDigit())
            .lineLimit(1)
            .fixedSize()
        }
    }

    private func dots(pitch: CGFloat, whole: Bool, shown: Double) -> some View {
        ZStack(alignment: .leading) {
            DotMatrixText(text: whole ? total.bahtWhole : total.baht, pitch: pitch).hidden()
            DotMatrixText(text: whole ? shown.bahtWhole : shown.baht, pitch: pitch)
        }
    }

    @ViewBuilder
    private func stats(_ point: SpendPoint) -> some View {
        Text(shortTitle(point.date)).fontWeight(.semibold).foregroundStyle(Theme.ink)
            .accessibilityLabel(range.bucketTitle(for: point.date))
        stat("Spent", point.amount.bahtWhole)
        if point.count > 1 {
            stat("High", point.high.bahtWhole)
            stat("Low", point.low.bahtWhole)
        }
        stat("Receipts", "\(point.count)")
    }

    /// "Tue 13 Oct", "13:00" or "Oct 2026": short enough to keep the line to one row.
    private func shortTitle(_ date: Date) -> String {
        switch range {
        case .day: date.formatted(.dateTime.hour().minute())
        case .week, .month: date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        case .year: date.formatted(.dateTime.month(.abbreviated).year())
        }
    }

    private func stat(_ name: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(name).foregroundStyle(Theme.muted)
            Text(value).foregroundStyle(Theme.ink)
        }
    }
}

/// "▲ 12.3% vs previous 30 days": spending going up is red, down is green, and the arrow says it too.
struct ChangeLabel: View {
    let total: Double
    let previous: Double
    let range: TimeRange
    var comparisonName = ""
    private var against: String { comparisonName.isEmpty ? "previous \(range.longName)" : comparisonName }

    var body: some View {
        if previous > 0 {
            let change = (total - previous) / previous
            let up = change >= 0
            HStack(spacing: 6) {
                Label("\(up ? "+" : "−")\(abs(change).percent)", systemImage: up ? "arrowtriangle.up.fill" : "arrowtriangle.down.fill")
                    .font(Theme.figure(.subheadline))
                    .foregroundStyle(up ? Theme.up : Theme.down)
                Text("vs \(against)").font(.subheadline).foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(abs(change).percent) \(up ? "more" : "less") than \(against)")
        } else {
            Text("Nothing to compare with yet").font(.subheadline).foregroundStyle(Theme.muted)
        }
    }
}

/// The control strip: 01 a timeframe knob beside the timeframe keys, 02 chart-type keys in the
/// OP-1 encoder colours, 03 the indicators key.
struct ChartToolbar: View {
    @Binding var range: TimeRange
    @Binding var style: ChartStyle
    @Binding var showAverage: Bool
    @Binding var showPrevious: Bool
    let averageName: String
    @Environment(\.dynamicTypeSize) private var typeSize

    private func colour(_ style: ChartStyle) -> Color {
        switch style {
        case .line: Theme.keyBlue
        case .bars: Theme.keyGreen
        case .candles: Theme.keyGrey
        }
    }

    var body: some View {
        // Side by side when there's room (iPad); otherwise the big range knob gets its own row.
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 10) { rangeGroup; keyGroup }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .bottom, spacing: 10) { rangeGroup; keyGroup }
                VStack(alignment: .leading, spacing: 10) { rangeGroup; keyGroup }
            }
        }
    }

    private var rangeGroup: some View {
        VStack(alignment: .leading, spacing: 4) {
            ParameterLabel(number: 1, text: "range")
            HStack(spacing: 10) {
                Knob(title: "Time range", options: TimeRange.allCases, selection: $range, label: \.longName, size: 66)
                SegmentedBar(title: "Time range", options: TimeRange.allCases, selection: $range) { $0.rawValue }
            }
        }
    }

    private var keyGroup: some View {
            HStack(alignment: .bottom, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    ParameterLabel(number: 2, text: "chart")
                    HStack(spacing: 4) {
                        ForEach(ChartStyle.allCases) { option in
                            HardwareKey(symbol: option.symbol, title: option.name, colour: colour(option), isOn: option == style) {
                                style = option
                            }
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    ParameterLabel(number: 3, text: "fx")
                    Menu {
                        Toggle(averageName, isOn: $showAverage)
                        Toggle("Previous period", isOn: $showPrevious)
                    } label: {
                        VStack(spacing: 3) {
                            LED(on: showAverage || showPrevious)
                            Image(systemName: "function")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(Theme.onBright)
                                .frame(width: 34, height: 30)
                                .background(Theme.keyOrange, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                            Text("indicators").font(.system(size: 9, weight: .medium, design: Skin.current.design)).foregroundStyle(Theme.muted).fixedSize()
                        }
                        .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityLabel("Indicators")
                }
            }
    }
}

/// "Earlier", the period's dates, "Later", and a way back to today.
struct PeriodPager: View {
    let label: String
    let canGoEarlier: Bool
    let canGoLater: Bool
    let onPage: (Int) -> Void
    let onToday: () -> Void
    /// The calendar that opens from the dates.
    let picker: PeriodPicker
    @State private var picking = LaunchOption.string("picker") == "YES"

    var body: some View {
        HStack(spacing: 6) {
            pageButton("Earlier", symbol: "chevron.left", enabled: canGoEarlier) { onPage(-1) }
            Button {
                KeyClick.play()
                picking = true
            } label: {
                HStack(spacing: 5) {
                    if Skin.current == .gruv {
                        Text("cal:").font(Theme.figure(.footnote)).foregroundStyle(Theme.accentText)
                    } else {
                        Image(systemName: "calendar")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.accentText)
                    }
                    Text(Skin.current == .gruv ? label.uppercased() : label)
                        .font(Theme.figure(.footnote))
                        .foregroundStyle(Theme.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .padding(.horizontal, 10)
                .frame(minHeight: 44)
                .background { labelBackground }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Showing \(label)")
            .accessibilityHint("Opens a calendar to pick the period")
            .popover(isPresented: $picking) {
                picker
                    .presentationCompactAdaptation(.sheet)
                    .presentationDetents([.medium, .large])
                    .presentationBackground(Theme.surface)
            }
            pageButton("Later", symbol: "chevron.right", enabled: canGoLater) { onPage(1) }
            Spacer(minLength: 4)
            if canGoLater {
                Button(action: onToday) {
                    Label("Today", systemImage: "arrow.uturn.forward")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to today")
            }
        }
    }

    /// Outlined on console, plain on classic, bracketed on gruv, a soft pill on kawaii.
    @ViewBuilder private var labelBackground: some View {
        switch Skin.current {
        case .console: Rectangle().strokeBorder(Theme.line, lineWidth: 1).frame(height: 32)
        case .classic: EmptyView()
        case .gruv: Rectangle().strokeBorder(Theme.line, lineWidth: 2).frame(height: 32)
        case .kawaii: Capsule().fill(Theme.accent.opacity(0.14)).frame(height: 34)
        }
    }

    private func pageButton(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Group {
                switch Skin.current {
                case .console:
                    // A ringed button, so it's clear the arrows are how you move between periods.
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.heavy))
                        .foregroundStyle(enabled ? Theme.accentText : Theme.quiet)
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(enabled ? Theme.accent.opacity(0.14) : Color.clear))
                        .overlay(Circle().strokeBorder(enabled ? Theme.accent : Theme.line, lineWidth: enabled ? 2 : 1))
                case .classic:
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(enabled ? Theme.ink : Theme.quiet)
                        .frame(width: 32, height: 32)
                        .background(RoundedRectangle(cornerRadius: 4).fill(enabled ? Theme.line.opacity(0.6) : .clear))
                case .gruv:
                    Text(symbol == "chevron.left" ? "[<]" : "[>]")
                        .font(.system(.subheadline, design: .monospaced, weight: .bold))
                        .foregroundStyle(enabled ? Theme.accentText : Theme.quiet)
                case .kawaii:
                    Image(systemName: symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(enabled ? Theme.onAccent : Theme.quiet)
                        .frame(width: 36, height: 36)
                        .background(Circle().fill(enabled ? Theme.accent : Theme.line.opacity(0.5)))
                }
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel("\(title) period")
    }
}

// MARK: - Chart

/// The main pane: the running total as a line over a soft gradient, or each bucket as bars or
/// candlesticks. Red candles cost more than the bucket before and are filled; green ones cost less
/// and are hollow, so the difference never rests on colour alone.
struct SpendChart: View {
    let points: [SpendPoint]
    var previous: [SpendPoint] = []
    var average: [Double] = []
    let interval: DateInterval
    let range: TimeRange
    let style: ChartStyle
    let selected: SpendPoint?
    @Binding var selectedDate: Date?
    /// −1 for an earlier period, +1 for a later one.
    var onPage: (Int) -> Void = { _ in }
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    /// The top of the value axis: everything plotted fits, with a little headroom; it always starts at 0.
    private var yMax: Double {
        var values = points.map { value(of: $0) }
        if style == .candles { values += points.map(\.open) }
        values += previous.map { value(of: $0) } + average
        return max((values.max() ?? 0) * 1.08, 1)
    }

    /// About 1.2% of the axis, so a day that cost the same as the day before still shows a mark.
    private var minimumCandleBody: Double { yMax * 0.012 }

    private func value(of point: SpendPoint) -> Double { style == .line ? point.cumulative : point.amount }

    /// While a bucket is under the crosshair, the others fade so it stands out.
    private func fade(_ point: SpendPoint) -> Double {
        guard let selected else { return 1 }
        return point.date == selected.date ? 1 : 0.3
    }

    /// The last bucket with anything in it, for the last-value tag on the price axis.
    private var last: SpendPoint? { style == .line ? points.last : points.last { $0.count > 0 } }

    var body: some View {
        Chart {
            ForEach(Array(points.enumerated()), id: \.element.id) { index, point in
                mainMarks(point)
                indicatorMarks(point, index: index)
            }
            lastValueMarks
            crosshairMarks
        }
        .chartXScale(domain: interval.start...interval.end)
        .chartYScale(domain: 0...yMax)
        // Touching the chart only moves the crosshair; the circled arrows above it turn the page.
        .chartXSelection(value: $selectedDate)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel {
                    if let amount = value.as(Double.self) {
                        Text(amount.bahtCompact).font(Theme.smallLabel).frame(width: 46, alignment: .leading)
                    }
                }
                .foregroundStyle(Theme.muted)
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: typeSize >= .xxLarge ? 3 : 5)) { _ in
                AxisGridLine().foregroundStyle(Theme.line)
                AxisValueLabel(format: range.axisFormat).font(Theme.smallLabel).foregroundStyle(Theme.muted)
            }
        }
        .chartLegend(.hidden)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .accessibilityLabel("Spending chart")
        .accessibilityValue(accessibilitySummary)
        .animation(reduceMotion ? nil : .snappy, value: style)
        .animation(reduceMotion ? nil : .snappy, value: range)
    }

    @ChartContentBuilder
    private func mainMarks(_ point: SpendPoint) -> some ChartContent {
        switch style {
        case .line:
            AreaMark(x: .value("Time", point.date), y: .value("Running total", point.cumulative))
                .foregroundStyle(LinearGradient(colors: [ChartLook.line.opacity(ChartLook.areaTop), ChartLook.line.opacity(ChartLook.areaBottom)],
                                                startPoint: .top, endPoint: .bottom))
                .interpolationMethod(ChartLook.interpolation)
            LineMark(x: .value("Time", point.date), y: .value("Running total", point.cumulative), series: .value("Series", "This period"))
                .foregroundStyle(ChartLook.line)
                .lineStyle(StrokeStyle(lineWidth: ChartLook.lineWidth, lineCap: .round, lineJoin: .round))
                .interpolationMethod(ChartLook.interpolation)
        case .bars:
            BarMark(x: .value("Time", point.date, unit: range.bucketUnit), y: .value("Spent", point.amount))
                .foregroundStyle(point.date == selected?.date ? Theme.accent : ChartLook.bar)
                .opacity(fade(point))
                .cornerRadius(ChartLook.barCorner)
        case .candles:
            candleMarks(point)
        }
    }

    @ChartContentBuilder
    private func candleMarks(_ point: SpendPoint) -> some ChartContent {
        if !point.isEmptyCandle {
            let candle = point.candleBody(minimumHeight: minimumCandleBody)
            let color = point.isFlat ? Theme.muted : point.rose ? Theme.candleUp : Theme.candleDown
            RectangleMark(x: .value("Time", point.date, unit: range.bucketUnit),
                          yStart: .value("Open", candle.lowerBound), yEnd: .value("Close", candle.upperBound),
                          width: .ratio(0.62))
                .foregroundStyle(color)
                .opacity(fade(point))
                .cornerRadius(1.5)
            // Cheaper than the bucket before: hollow, so up and down differ by shape as well as colour.
            if !point.rose, !point.isFlat, candle.upperBound - candle.lowerBound > minimumCandleBody * 2.5 {
                RectangleMark(x: .value("Time", point.date, unit: range.bucketUnit),
                              yStart: .value("Open", candle.lowerBound + minimumCandleBody * 0.6),
                              yEnd: .value("Close", candle.upperBound - minimumCandleBody * 0.6),
                              width: .ratio(0.42))
                    .foregroundStyle(Theme.surface)
            }
        }
    }

    @ChartContentBuilder
    private func indicatorMarks(_ point: SpendPoint, index: Int) -> some ChartContent {
        if index < previous.count {
            LineMark(x: .value("Time", point.date), y: .value("Previous period", value(of: previous[index])),
                     series: .value("Series", "Previous period"))
                .foregroundStyle(Theme.quiet)
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .interpolationMethod(.monotone)
        }
        if index < average.count {
            LineMark(x: .value("Time", point.date, unit: range.bucketUnit), y: .value("Average", average[index]),
                     series: .value("Series", "Average"))
                .foregroundStyle(Theme.indicator)
                .lineStyle(StrokeStyle(lineWidth: 2))
                .interpolationMethod(.monotone)
        }
    }

    /// The last value, tagged on the price axis.
    @ChartContentBuilder
    private var lastValueMarks: some ChartContent {
        if let last, selected == nil {
            RuleMark(y: .value("Last", value(of: last)))
                .foregroundStyle(Theme.ink.opacity(0.35))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                .annotation(position: .trailing, alignment: .center, spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    tag(value(of: last).bahtCompact, fill: Theme.ink, text: Theme.surface)
                }
        }
    }

    @ChartContentBuilder
    private var crosshairMarks: some ChartContent {
        if let selected {
            // On bars and candles the crosshair runs through the middle of the bucket, where they're drawn.
            RuleMark(x: style == .line ? .value("Selected", selected.date) : .value("Selected", selected.date, unit: range.bucketUnit))
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                // The date sits on the time axis, as on TradingView, clear of the period label above.
                .annotation(position: .bottom, spacing: 2, overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    tag(selected.date.formatted(range.axisFormat), fill: Theme.accent)
                }
            RuleMark(y: .value("Selected value", value(of: selected)))
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .trailing, alignment: .center, spacing: 0,
                            overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                    tag(value(of: selected).bahtCompact, fill: Theme.accent)
                }
            if style == .line {
                PointMark(x: .value("Selected", selected.date), y: .value("Running total", selected.cumulative))
                    .symbolSize(60)
                    .foregroundStyle(Theme.accent)
            }
        }
    }

    private var accessibilitySummary: String {
        let total = points.reduce(0) { $0 + $1.amount }
        guard let peak = points.max(by: { $0.amount < $1.amount }), total > 0 else { return "Nothing spent in this period" }
        return "\(style.name) chart. \(total.baht) in total; the most was \(peak.amount.baht) on \(range.bucketTitle(for: peak.date))."
    }

    private func tag(_ text: String, fill: Color, text colour: Color = Theme.onAccent) -> some View {
        Text(text)
            .font(Theme.figure(.caption2))
            .foregroundStyle(colour)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(fill, in: RoundedRectangle(cornerRadius: 3))
    }
}

/// What the lines and marks mean, in words.
struct ChartLegend: View {
    let style: ChartStyle
    let showAverage: Bool
    let averageName: String
    let showPrevious: Bool

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.system(.caption2, design: Skin.current.design))
        .foregroundStyle(Theme.muted)
    }

    @ViewBuilder
    private var items: some View {
        switch style {
        case .line: key(Theme.ink, "running total")
        case .bars: key(Theme.ink, "spent per bucket")
        case .candles:
            key(Theme.candleUp, "▲ filled: up from the one before")
            key(Theme.candleDown, "▽ hollow: down")
        }
        if showAverage { key(Theme.indicator, averageName) }
        if showPrevious { key(Theme.quiet, "previous period", dashed: true) }
    }

    private func key(_ colour: Color, _ text: String, dashed: Bool = false) -> some View {
        HStack(spacing: 5) {
            Capsule().fill(colour).frame(width: dashed ? 6 : 12, height: 3)
            if dashed { Capsule().fill(colour).frame(width: 6, height: 3) }
            Text(text)
        }
    }
}

extension SpendPoint {
    /// From the bucket before's spending to this one's, at least `minimumHeight` tall so a flat
    /// day still shows. A thin body grows upward from its lower end, never below zero.
    func candleBody(minimumHeight: Double) -> ClosedRange<Double> {
        let low = min(open, close), high = max(open, close)
        return low...max(high, low + minimumHeight)
    }
}

/// The chart's marks per style: an ink line on console, TradingView's blue area on classic,
/// a stepped orange trace on gruv, a thick soft pink curve and round bars on kawaii.
enum ChartLook {
    static var line: Color { Skin.current == .console ? Theme.ink : Theme.accent }
    static var bar: Color {
        switch Skin.current {
        case .console, .gruv: Theme.ink
        case .classic: Theme.chartBlue
        case .kawaii: Theme.accent.opacity(0.75)
        }
    }
    static var lineWidth: CGFloat {
        switch Skin.current {
        case .console, .classic: 2
        case .gruv: 1.5
        case .kawaii: 3.5
        }
    }
    static var interpolation: InterpolationMethod {
        switch Skin.current {
        case .gruv: .stepEnd
        case .kawaii: .catmullRom
        default: .monotone
        }
    }
    static var areaTop: Double { Skin.current == .gruv ? 0.14 : Skin.current == .kawaii ? 0.3 : 0.18 }
    static var areaBottom: Double { Skin.current == .gruv ? 0.14 : 0 }
    static var barCorner: CGFloat {
        switch Skin.current {
        case .console: 1
        case .classic: 0
        case .gruv: 0
        case .kawaii: 6
        }
    }
}

// MARK: - Cards

/// The receipts behind the point under the crosshair.
struct BucketReceiptsCard: View {
    let title: String
    let receipts: [Receipt]
    let onClear: () -> Void

    var body: some View {
        Card(title: title, subtitle: receipts.isEmpty ? "Nothing spent" : "\(receipts.count) receipt\(receipts.count == 1 ? "" : "s")") {
            VStack(spacing: 0) {
                ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                    if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                    NavigationLink {
                        ReceiptDetailView(receipt: receipt)
                    } label: {
                        ReceiptRow(receipt: receipt, showsCategory: true).padding(.vertical, 6)
                    }
                    .buttonStyle(.plain)
                }
                Button(action: onClear) {
                    Label("Clear crosshair", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accentText)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct WatchlistRow: Identifiable {
    let category: SpendCategory
    let amount: Double
    let previous: Double
    let share: Double
    /// Spending per bucket, for the sparkline.
    let spark: [Double]
    var id: SpendCategory { category }
    var change: Double? { previous > 0 ? (amount - previous) / previous : nil }
}

/// Categories like a watchlist: a sparkline, the amount, and the change from the period before.
/// Tap one to chart it.
struct WatchlistCard: View {
    let rows: [WatchlistRow]
    let periodName: String
    let selected: SpendCategory?
    let onSelect: (SpendCategory?) -> Void

    var body: some View {
        Card(title: "Watchlist", subtitle: "Categories · \(periodName) · tap one to chart it") {
            if rows.isEmpty {
                Text("Nothing spent in this period.").foregroundStyle(Theme.muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        Button { onSelect(selected == row.category ? nil : row.category) } label: {
                            WatchlistRowView(row: row, isSelected: selected == row.category)
                                .opacity(selected == nil || selected == row.category ? 1 : 0.45)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == row.category ? .isSelected : [])
                        .accessibilityHint(selected == row.category ? "Shows all spending again" : "Charts this category")
                    }
                }
            }
        }
    }
}

struct WatchlistRowView: View {
    let row: WatchlistRow
    let isSelected: Bool

    var body: some View {
        AdaptiveStack(spacing: 10) {
            HStack(spacing: 10) {
                LED(on: true, colour: isSelected ? Theme.accent : row.category.color)
                CategoryIcon(symbol: row.category.symbol, size: 28, fill: row.category.color)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.category.name).font(.system(.subheadline, weight: isSelected ? .heavy : .semibold)).foregroundStyle(Theme.ink)
                    Text("\(row.share.percent) of spending").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 6)
            Sparkline(values: row.spark, colour: (row.change ?? 0) > 0 ? Theme.candleUp : Theme.candleDown)
                .frame(width: 64, height: 24)
                .accessibilityHidden(true)
            VStack(alignment: .trailing, spacing: 1) {
                Text(row.amount.bahtWhole).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                if let change = row.change {
                    Text("\(change >= 0 ? "▲" : "▼") \(abs(change).percent)")
                        .font(Theme.figure(.caption))
                        .foregroundStyle(change >= 0 ? Theme.up : Theme.down)
                } else {
                    Text("new").font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .fixedSize()
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(isSelected ? Theme.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(isSelected ? Theme.accent : Color.clear, lineWidth: 2))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// A tiny line of the values, scaled to fit.
struct Sparkline: View {
    let values: [Double]
    let colour: Color

    var body: some View {
        Canvas { context, size in
            guard values.count > 1, let top = values.max(), top > 0 else { return }
            var path = Path()
            for (i, value) in values.enumerated() {
                let point = CGPoint(x: size.width * Double(i) / Double(values.count - 1),
                                    y: size.height - size.height * value / top)
                if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
            }
            context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: 1.5, lineJoin: .round))
        }
    }
}

struct RecentReceiptsCard: View {
    let receipts: [Receipt]
    var onScan: () -> Void
    /// While a category or type is picked, receipts that match stand out and the rest fade.
    var matches: ((Receipt) -> Bool)? = nil

    var body: some View {
        Card(title: "Latest receipts") {
            if receipts.isEmpty {
                Button(action: onScan) {
                    Label("Scan your first receipt", systemImage: "doc.viewfinder")
                }
                .buttonStyle(BlockButtonStyle(prominent: true))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(receipts.enumerated()), id: \.element.id) { index, receipt in
                        if index > 0 { Rectangle().fill(Theme.line).frame(height: 1) }
                        let hit = matches?(receipt)
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            ReceiptRow(receipt: receipt)
                                .padding(.vertical, 6)
                                .padding(.leading, hit == true ? 8 : 0)
                                .overlay(alignment: .leading) {
                                    if hit == true { Rectangle().fill(Theme.accent).frame(width: 3).padding(.vertical, 6) }
                                }
                                .opacity(hit == false ? 0.4 : 1)
                        }
                        .buttonStyle(.plain)
                        .accessibilityValue(hit == true ? "Matches" : "")
                    }
                }
            }
        }
    }
}

struct TypeTileRow: Identifiable {
    let category: SpendCategory
    let total: Double
    let count: Int
    var id: SpendCategory { category }

    /// The categories the tiles show, in order: two rows of four on an iPhone.
    static let order: [SpendCategory] = [
        .dining, .transport, .shopping, .groceries, .utilities, .health, .home, .entertainment,
    ]

    /// Every shown category's spending, all time.
    static func rows(_ all: SpendingAnalyzer) -> [TypeTileRow] {
        order.map { category in
            let inside = all.only(category).receipts
            return TypeTileRow(category: category, total: inside.reduce(0) { $0 + $1.total }, count: inside.count)
        }
    }

    /// Short enough for a quarter of an iPhone's width.
    var shortName: String {
        switch category {
        case .dining: "food & drink"
        case .transport: "transport"
        case .entertainment: "entertain"
        default: category.name.lowercased()
        }
    }
}

/// One key per spending category with its all-time total. Tap to list every receipt in it.
struct TypeTiles: View {
    let rows: [TypeTileRow]
    let onSelect: (SpendCategory) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ParameterLabel(number: 1, text: "receipt type")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: typeSize.isAccessibilitySize ? 1 : typeSize >= .xxLarge ? 2 : 4), spacing: 6) {
                ForEach(rows) { row in
                    Button { KeyClick.play(); onSelect(row.category) } label: {
                        VStack(spacing: 3) {
                            Image(systemName: row.category.symbol)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundStyle(Theme.onBright)
                                .frame(width: 44, height: 44)
                                .background(row.category.color, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                            Text(row.shortName)
                                .font(.system(.caption2, design: Skin.current.design, weight: .medium))
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                                .minimumScaleFactor(0.6)
                        }
                        .padding(.vertical, 6)
                        .padding(.horizontal, 3)
                        .frame(maxWidth: .infinity, minHeight: 74)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: min(Theme.radius, 20), style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: min(Theme.radius, 20), style: .continuous).strokeBorder(Theme.line, lineWidth: Theme.rule))
                        .shadow(color: Theme.ink.opacity(Theme.shadow > 0 ? 0.07 : 0), radius: Theme.shadow, y: 3)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(row.category.name)
                    .accessibilityAddTraits(.isButton)
                    .accessibilityHint("Lists every receipt in this category")
                }
            }
        }
    }
}

/// Every receipt with something in one category, newest first, grouped by month. Amounts are
/// what each receipt spent on that category, so a mixed receipt counts only its share.
struct CategoryReceiptList: View {
    let category: SpendCategory
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date, order: .reverse) private var receipts: [Receipt]
    @State private var search = ""

    var body: some View {
        let inCategory = receipts.compactMap { receipt -> (Receipt, Double)? in
            guard let amount = ReceiptSnapshot(receipt).categoryAmounts[category], amount > 0.005 else { return nil }
            return (receipt, amount)
        }
        let shown = inCategory.filter { ReceiptSearch.matches(search, $0.0.searchFields) }
        let months = Dictionary(grouping: shown) { $0.0.date.startOfMonth }.sorted { $0.key > $1.key }
        List {
            Section {
                HStack(spacing: 12) {
                    CategoryIcon(symbol: category.symbol, size: 40, fill: category.color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(shown.reduce(0) { $0 + $1.1 }.baht).font(Theme.figure(.title2)).foregroundStyle(Theme.ink)
                        Text("\(shown.count) receipt\(shown.count == 1 ? "" : "s")\(search.isEmpty ? " · all time" : " matching")")
                            .font(.system(.footnote, design: Skin.current.design)).foregroundStyle(Theme.muted)
                    }
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }
            .listRowBackground(Theme.surface)
            ForEach(months, id: \.key) { month, items in
                Section {
                    ForEach(items, id: \.0.persistentModelID) { receipt, _ in
                        NavigationLink { ReceiptDetailView(receipt: receipt) } label: { ReceiptRow(receipt: receipt) }
                    }
                    .listRowBackground(Theme.surface)
                } header: {
                    HStack {
                        TitleChip(month.formatted(.dateTime.month(.wide).year()))
                        Spacer()
                        Text(items.reduce(0) { $0 + $1.1 }.bahtWhole).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                    }
                    .textCase(nil)
                }
            }
        }
        .listStyle(.plain)
        .environment(\.searchHighlight, search)
        .paperBackground()
        .searchable(text: $search, prompt: "Search \(category.name.lowercased())")
        .navigationTitle(category.name)
        .overlay {
            if inCategory.isEmpty {
                ContentUnavailableView("No \(category.name.lowercased()) receipts yet", systemImage: category.symbol)
            } else if shown.isEmpty {
                ContentUnavailableView.search(text: search)
            }
        }
    }
}
