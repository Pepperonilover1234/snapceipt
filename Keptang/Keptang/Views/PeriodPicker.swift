import SwiftUI

/// The chart's calendar: a month of days for 1D, the same month with only Sundays live for 7D,
/// twelve months for 1M and the years with receipts for 1Y. Picking jumps the chart there.
struct PeriodPicker: View {
    let rules: PeriodPicking
    /// The period the chart is showing now.
    let showing: DateInterval
    /// Days (at midnight) that have receipts.
    let receiptDays: Set<Date>
    let onPick: (Date) -> Void
    @State private var page: Date
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var calendar: Calendar { rules.calendar }
    private var range: TimeRange { rules.range }

    init(rules: PeriodPicking, showing: DateInterval, receiptDays: Set<Date>, onPick: @escaping (Date) -> Void) {
        self.rules = rules
        self.showing = showing
        self.receiptDays = receiptDays
        self.onPick = onPick
        _page = State(initialValue: showing.start)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                ParameterLabel(number: 1, text: heading)
                Spacer()
                Button {
                    pick(rules.now)
                } label: {
                    Text(Theme.cased(range.currentName))
                        .font(Theme.label)
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 10)
                        .frame(minHeight: 36)
                        .overlay(Capsule().strokeBorder(Theme.accent, lineWidth: 1.5))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Jump to \(range.currentName.lowercased())")
            }
            switch range {
            case .day, .week: dayGrid
            case .month: monthGrid
            case .year: yearGrid
            }
            if range == .week {
                Text("weeks run sunday to saturday · pick a sunday")
                    .font(Theme.smallLabel)
                    .foregroundStyle(Theme.muted)
            }
        }
        .padding(16)
        .frame(minWidth: 320, idealWidth: 360, maxWidth: 420, alignment: .top)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.surface)
    }

    private var heading: String {
        switch range {
        case .day: "pick a day"
        case .week: "pick a week"
        case .month: "pick a month"
        case .year: "pick a year"
        }
    }

    private func pick(_ date: Date) {
        KeyClick.play()
        onPick(date)
        dismiss()
    }

    // MARK: Pages

    /// "‹ October 2026 ›" over the day grid, "‹ 2026 ›" over the month grid.
    private func pageHeader(title: String, unit: Calendar.Component) -> some View {
        let earlier = calendar.date(byAdding: unit, value: -1, to: page)!
        let later = calendar.date(byAdding: unit, value: 1, to: page)!
        let canGoEarlier = calendar.dateInterval(of: unit, for: earlier)!.end > rules.earliestStart
        let canGoLater = calendar.dateInterval(of: unit, for: later)!.start <= rules.now
        return HStack {
            arrow("chevron.left", label: "Earlier", enabled: canGoEarlier) { page = earlier }
            Spacer()
            Text(title).font(Theme.figure(.subheadline)).fontWeight(.semibold).foregroundStyle(Theme.ink)
                .accessibilityAddTraits(.isHeader)
            Spacer()
            arrow("chevron.right", label: "Later", enabled: canGoLater) { page = later }
        }
    }

    private func arrow(_ symbol: String, label: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            if reduceMotion { action() } else { withAnimation(.snappy) { action() } }
        } label: {
            Image(systemName: symbol)
                .font(.subheadline.weight(.heavy))
                .foregroundStyle(enabled ? Theme.accentText : Theme.quiet)
                .frame(width: 34, height: 34)
                .overlay(Circle().strokeBorder(enabled ? Theme.accent : Theme.line, lineWidth: enabled ? 2 : 1))
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    // MARK: Days and weeks

    private var dayGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let weekdays = calendar.veryShortStandaloneWeekdaySymbols   // Sunday first
        return VStack(spacing: 8) {
            pageHeader(title: page.formatted(.dateTime.month(.wide).year()), unit: .month)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(weekdays.enumerated()), id: \.offset) { index, symbol in
                    Text(Theme.cased(symbol))
                        .font(Theme.smallLabel)
                        .foregroundStyle(range == .week && index == 0 ? Theme.accentText : Theme.muted)
                        .accessibilityHidden(true)
                }
                ForEach(Array(rules.grid(for: page).enumerated()), id: \.offset) { _, day in
                    if let day { dayCell(day) } else { Color.clear.frame(height: 44) }
                }
            }
        }
    }

    private func dayCell(_ day: Date) -> some View {
        let selectable = rules.isSelectable(day: day)
        let inShowing = day >= showing.start && day < showing.end
        // For a week the whole row lights up; the Sunday that starts it is solid.
        let solid = inShowing && (range == .day || rules.isSunday(day))
        let isToday = calendar.isDate(day, inSameDayAs: rules.now)
        let hasReceipts = receiptDays.contains(calendar.startOfDay(for: day))
        return Button { pick(day) } label: {
            VStack(spacing: 2) {
                Text("\(calendar.component(.day, from: day))")
                    .font(Theme.figure(.subheadline))
                    .fontWeight(solid ? .bold : .regular)
                    .foregroundStyle(solid ? Theme.onAccent : selectable ? Theme.ink : Theme.quiet)
                Circle()
                    .fill(hasReceipts ? (solid ? Theme.onAccent : Theme.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                Rectangle().fill(solid ? Theme.accent : inShowing ? Theme.accent.opacity(0.18) : .clear)
            )
            .overlay(Rectangle().strokeBorder(isToday ? Theme.ink : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!selectable)
        .accessibilityLabel(dayLabel(day, hasReceipts: hasReceipts, isToday: isToday))
        .accessibilityHint(selectable ? "" : "Not selectable")
        .accessibilityAddTraits(solid ? .isSelected : [])
    }

    private func dayLabel(_ day: Date, hasReceipts: Bool, isToday: Bool) -> String {
        var parts = [day.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if range == .week && rules.isSunday(day) { parts[0] = "Week starting \(parts[0])" }
        if isToday { parts.append("today") }
        if hasReceipts { parts.append("has receipts") }
        return parts.joined(separator: ", ")
    }

    // MARK: Months and years

    private var monthGrid: some View {
        let year = calendar.dateInterval(of: .year, for: page)!.start
        let months = (0..<12).map { calendar.date(byAdding: .month, value: $0, to: year)! }
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return VStack(spacing: 8) {
            pageHeader(title: page.formatted(.dateTime.year()), unit: .year)
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(months, id: \.self) { month in
                    let interval = calendar.dateInterval(of: .month, for: month)!
                    let hasReceipts = receiptDays.contains { $0 >= interval.start && $0 < interval.end }
                    periodKey(title: month.formatted(.dateTime.month(.abbreviated)).lowercased(),
                              spoken: month.formatted(.dateTime.month(.wide).year()),
                              selected: showing.start == interval.start,
                              current: rules.now >= interval.start && rules.now < interval.end,
                              enabled: rules.isSelectable(month: month),
                              hasReceipts: hasReceipts) { pick(month) }
                }
            }
        }
    }

    private var yearGrid: some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        return LazyVGrid(columns: columns, spacing: 6) {
            ForEach(rules.years, id: \.self) { year in
                let interval = calendar.dateInterval(of: .year, for: year)!
                periodKey(title: year.formatted(.dateTime.year()),
                          spoken: year.formatted(.dateTime.year()),
                          selected: showing.start == interval.start,
                          current: rules.now >= interval.start && rules.now < interval.end,
                          enabled: true,
                          hasReceipts: receiptDays.contains { $0 >= interval.start && $0 < interval.end }) { pick(year) }
            }
        }
    }

    /// A month or year key: orange when it's the one on the chart, outlined when it's now.
    private func periodKey(title: String, spoken: String, selected: Bool, current: Bool, enabled: Bool,
                           hasReceipts: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Text(title)
                    .font(Theme.figure(.subheadline))
                    .fontWeight(selected ? .bold : .medium)
                    .foregroundStyle(selected ? Theme.onAccent : enabled ? Theme.ink : Theme.quiet)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Circle()
                    .fill(hasReceipts ? (selected ? Theme.onAccent : Theme.accent) : .clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(selected ? Theme.accent : Theme.paper, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .strokeBorder(current ? Theme.ink : Theme.line, lineWidth: current ? 1.5 : 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel([spoken, current ? "now" : nil, hasReceipts ? "has receipts" : nil].compactMap { $0 }.joined(separator: ", "))
        .accessibilityHint(enabled ? "" : "Not selectable")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
