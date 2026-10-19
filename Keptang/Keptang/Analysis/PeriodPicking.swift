import Foundation

/// What the chart's calendar lets you pick for each range: any day for 1D, only Sundays for 7D
/// (each starts a Sunday-to-Saturday week), a month for 1M and a year for 1Y. Nothing in the
/// future, and nothing before the period holding the first receipt.
struct PeriodPicking {
    let range: TimeRange
    let now: Date
    /// The first receipt's date; nil when there are none.
    let firstReceipt: Date?
    var calendar: Calendar = .app

    /// The start of the earliest period with anything in it (the current one when there's nothing).
    var earliestStart: Date {
        range.interval(endingAt: firstReceipt ?? now, calendar: calendar).start
    }

    func isSelectable(day: Date) -> Bool {
        let start = calendar.startOfDay(for: day)
        guard start <= now, start >= calendar.startOfDay(for: earliestStart) else { return false }
        return range == .week ? isSunday(start) : true
    }

    func isSelectable(month: Date) -> Bool {
        let interval = calendar.dateInterval(of: .month, for: month)!
        return interval.start <= now && interval.end > earliestStart
    }

    /// Every year from the first receipt's to this one, oldest first.
    var years: [Date] {
        let first = calendar.component(.year, from: firstReceipt ?? now)
        let last = calendar.component(.year, from: now)
        return (first...max(first, last)).map { calendar.date(from: DateComponents(year: $0, month: 1, day: 1))! }
    }

    func isSunday(_ date: Date) -> Bool { calendar.component(.weekday, from: date) == 1 }

    /// The page a picked date lands on, ready for the chart.
    func offset(for picked: Date) -> Int {
        min(0, range.offset(of: picked, now: now, calendar: calendar))
    }

    /// The days of the month holding `month`, with blanks before the 1st so Sunday is the first column.
    func grid(for month: Date) -> [Date?] {
        let interval = calendar.dateInterval(of: .month, for: month)!
        let blanks = calendar.component(.weekday, from: interval.start) - 1
        let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day!
        let days = (0..<count).map { calendar.date(byAdding: .day, value: $0, to: interval.start)! }
        return Array(repeating: nil, count: blanks) + days
    }
}
