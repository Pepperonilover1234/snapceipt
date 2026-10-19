import SwiftData
import SwiftUI

/// A month of daily spending, from this month back 11 months. Navigation only:
/// older receipts are never deleted and stay in the list and search.
struct SpendingCalendarView: View {
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    /// 0 is this month, −11 the oldest month shown.
    @State private var monthOffset = -(Int(LaunchOption.string("calendarBack") ?? "") ?? 0)
    @Environment(\.pageAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    static let monthsShown = 12
    private let calendar = Calendar.app

    var body: some View {
        let analyzer = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let month = analyzer.month(containing: calendar.date(byAdding: .month, value: monthOffset, to: .now)!)
        let days = analyzer.dailyTotals(in: month)
        let monthTotal = analyzer.total(in: month)
        let busiest = days.values.map(\.total).max() ?? 0

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(month: month, total: monthTotal, count: days.values.reduce(0) { $0 + $1.count })

                VStack(spacing: 6) {
                    weekdayRow
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 6) {
                        ForEach(0..<leadingBlanks(for: month.start), id: \.self) { _ in
                            Color.clear.frame(minHeight: 48).accessibilityHidden(true)
                        }
                        ForEach(daysOf(month), id: \.self) { day in
                            NavigationLink {
                                DayReceiptsView(day: day)
                            } label: {
                                DayCell(day: day, spend: days[day], level: level(days[day]?.total ?? 0, busiest: busiest),
                                        isToday: calendar.isDateInToday(day))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(12)
                .block()
                .gesture(
                    DragGesture(minimumDistance: 30).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        moveMonth(value.translation.width > 0 ? -1 : 1)
                    }
                )
                .accessibilityAction(named: "Previous month") { moveMonth(-1) }
                .accessibilityAction(named: "Next month") { moveMonth(1) }

                legend
                Text("The calendar shows the last 12 months. Older receipts are kept and stay in the list and search.")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
            .padding()
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
    }

    // MARK: - Pieces

    private func header(month: DateInterval, total: Double, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                arrow("Previous month", symbol: "chevron.left", enabled: monthOffset > -(Self.monthsShown - 1)) { moveMonth(-1) }
                Text(month.start.formatted(.dateTime.month(.wide).year()))
                    .font(.system(.title3, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
                arrow("Next month", symbol: "chevron.right", enabled: monthOffset < 0) { moveMonth(1) }
            }
            AdaptiveStack(spacing: 10) {
                HeroFigure(text: total.baht, highlighted: true)
                Text(count == 0 ? "Nothing spent this month" : "\(count) receipt\(count == 1 ? "" : "s") this month")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var weekdayRow: some View {
        // Monday first, to match Calendar.app.
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let order = (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 }
        return HStack(spacing: 6) {
            ForEach(order, id: \.self) { index in
                Text(symbols[index])
                    .font(Theme.smallLabel)
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    private var legend: some View {
        HStack(spacing: 14) {
            ForEach(1...3, id: \.self) { level in
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4).fill(DayCell.fill(level: level, accent: accent))
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Theme.line, lineWidth: 1))
                        .frame(width: 18, height: 18)
                    Text(["Less", "More", "Most"][level - 1]).font(.footnote).foregroundStyle(Theme.muted)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Darker days cost more, within this month")
    }

    private func arrow(_ title: String, symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.body.weight(.heavy))
                .foregroundStyle(enabled ? Theme.ink : Theme.quiet)
                .frame(width: 48, height: 44)
                .block(radius: 12, shadow: enabled ? 3 : 0)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(title)
    }

    // MARK: - Maths

    private func moveMonth(_ step: Int) {
        let next = min(0, max(-(Self.monthsShown - 1), monthOffset + step))
        guard next != monthOffset else { return }
        if reduceMotion { monthOffset = next } else { withAnimation(.snappy) { monthOffset = next } }
    }

    private func daysOf(_ month: DateInterval) -> [Date] {
        var days: [Date] = []
        var day = month.start
        while day < month.end {
            days.append(day)
            day = calendar.date(byAdding: .day, value: 1, to: day)!
        }
        return days
    }

    private func leadingBlanks(for start: Date) -> Int {
        (calendar.component(.weekday, from: start) - calendar.firstWeekday + 7) % 7
    }

    /// 1, 2 or 3 by how the day compares with the month's busiest day; 0 when nothing was spent.
    private func level(_ total: Double, busiest: Double) -> Int {
        guard total > 0, busiest > 0 else { return 0 }
        let share = total / busiest
        return share > 2.0 / 3 ? 3 : share > 1.0 / 3 ? 2 : 1
    }
}

struct DayCell: View {
    let day: Date
    let spend: DayTotal?
    let level: Int
    let isToday: Bool
    @Environment(\.pageAccent) private var accent

    /// Solid tints of the tab colour, the same in light and dark, so navy text reads on all three.
    static func fill(level: Int, accent: Color) -> Color {
        switch level {
        case 1: Theme.accent.opacity(0.22)
        case 2: Theme.accent.opacity(0.55)
        case 3: Theme.accent
        default: Theme.surface
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 10, style: .continuous)
        let filled = level >= 3
        VStack(spacing: 2) {
            Text(day.formatted(.dateTime.day()))
                .font(.system(.subheadline, weight: .semibold))
            if let spend, spend.total > 0 {
                Text(spend.total.bahtCompact)
                    .font(.system(.caption2, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                Circle().frame(width: 5, height: 5)
            }
        }
        .foregroundStyle(filled ? Theme.onAccent : Theme.ink)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, minHeight: 52)
        .background(Self.fill(level: level, accent: accent), in: shape)
        .overlay(shape.strokeBorder(isToday ? Theme.accent : Theme.line, lineWidth: isToday ? 2.5 : 1))
        .contentShape(shape)
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Shows this day's receipts")
    }

    private var accessibilityText: String {
        let date = day.formatted(.dateTime.day().month(.wide))
        let today = isToday ? ", today" : ""
        guard let spend, spend.count > 0 else { return "\(date)\(today), nothing spent" }
        return "\(date)\(today), \(spend.total.baht), \(spend.count) receipt\(spend.count == 1 ? "" : "s")"
    }
}

/// Every receipt from one day, with the merchant, time, amount, category and photo.
struct DayReceiptsView: View {
    let day: Date
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }) private var receipts: [Receipt]

    init(day: Date) {
        self.day = day
        let interval = Calendar.app.dateInterval(of: .day, for: day)!
        let start = interval.start
        let end = interval.end
        _receipts = Query(filter: #Predicate<Receipt> { $0.date >= start && $0.date < end }, sort: \Receipt.date)
    }

    var body: some View {
        let analyzer = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let interval = analyzer.day(containing: day)
        let total = analyzer.total(in: interval)
        let dayColor = analyzer.categoryTotals(in: interval).first?.category.color ?? Theme.sky

        CardPage {
            VStack(alignment: .leading, spacing: 8) {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide).year()))
                    .font(Theme.label)
                    .foregroundStyle(Theme.muted)
                HeroFigure(text: total.baht, highlighted: true)
                    .environment(\.pageAccent, dayColor)
                Text(receipts.isEmpty ? "Nothing spent" : "\(receipts.count) receipt\(receipts.count == 1 ? "" : "s")")
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
            }
            .accessibilityElement(children: .combine)

            if !receipts.isEmpty {
                CardSection(title: "Receipts", color: .sky) {
                    ForEach(receipts) { receipt in
                        NavigationLink {
                            ReceiptDetailView(receipt: receipt)
                        } label: {
                            DayReceiptRow(receipt: receipt)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .navigationTitle(day.formatted(.dateTime.day().month(.abbreviated)))
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct DayReceiptRow: View {
    let receipt: Receipt
    @State private var thumbnail: UIImage?

    var body: some View {
        let category = receipt.kind.isBill ? receipt.kind.name : receipt.mainCategory.name
        AdaptiveStack(spacing: 12) {
            HStack(spacing: 12) {
                if let thumbnail {
                    Image(uiImage: thumbnail)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 48, height: 60)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                        .accessibilityHidden(true)
                } else {
                    CategoryIcon(symbol: receipt.iconSymbol, size: 44, fill: receipt.iconColor)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(receipt.shopName)
                        .font(.system(.body, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    Text(receipt.date.formatted(.dateTime.hour().minute()))
                        .font(.subheadline)
                        .foregroundStyle(Theme.muted)
                    Label(category, systemImage: receipt.iconSymbol)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 8)
            Text(receipt.total.baht)
                .font(Theme.figure())
                .foregroundStyle(Theme.ink)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityValue(receipt.imageData == nil ? "" : "Has a photo")
        .task(id: receipt.persistentModelID) {
            guard let data = receipt.imageData else { return }
            thumbnail = await UIImage(data: data)?.byPreparingThumbnail(ofSize: CGSize(width: 144, height: 180))
        }
    }
}
