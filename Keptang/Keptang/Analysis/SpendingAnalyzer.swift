import Foundation
import SwiftData

/// A plain copy of a saved receipt, so analysis is pure, fast and independent of SwiftData.
struct ReceiptSnapshot {
    /// The saved receipt this was copied from; nil in tests.
    let id: PersistentIdentifier?
    let date: Date
    let total: Double
    let vat: Double
    let shop: String
    let kind: ReceiptKind
    let isFullTaxInvoice: Bool
    let billUnits: Double
    /// Money per category; always adds up to `total`, so each baht is counted once.
    let categoryAmounts: [SpendCategory: Double]

    init(_ receipt: Receipt) {
        self.init(
            id: receipt.persistentModelID,
            date: receipt.date,
            total: receipt.total,
            vat: receipt.vat,
            shop: receipt.shopName,
            kind: receipt.kind,
            isFullTaxInvoice: receipt.isFullTaxInvoice,
            billUnits: receipt.billUnits,
            items: receipt.items.map { ($0.category, $0.total) }
        )
    }

    init(
        id: PersistentIdentifier? = nil,
        date: Date,
        total: Double,
        vat: Double = 0,
        shop: String = "",
        kind: ReceiptKind = .purchase,
        isFullTaxInvoice: Bool = false,
        billUnits: Double = 0,
        items: [(category: SpendCategory, total: Double)]
    ) {
        self.id = id
        self.date = date
        self.total = total
        self.vat = vat
        self.shop = shop
        self.kind = kind
        self.isFullTaxInvoice = isFullTaxInvoice
        self.billUnits = billUnits
        categoryAmounts = Self.categoryAmounts(total: total, kind: kind, items: items)
    }

    /// Splits the receipt total across its item categories. Bills are all Utilities.
    /// When the items don't add up to the total (a missed line, rounding, a discount),
    /// each category is scaled so the split still adds up to exactly the amount paid.
    static func categoryAmounts(total: Double, kind: ReceiptKind, items: [(category: SpendCategory, total: Double)]) -> [SpendCategory: Double] {
        if kind.isBill { return [.utilities: total] }
        var amounts: [SpendCategory: Double] = [:]
        for item in items { amounts[item.category, default: 0] += item.total }
        let sum = amounts.values.reduce(0, +)
        if amounts.isEmpty || sum <= 0 { return [.other: total] }
        if abs(sum - total) > 0.01 {
            for (category, value) in amounts { amounts[category] = value / sum * total }
        }
        return amounts
    }

    var mainCategory: SpendCategory {
        categoryAmounts.max { $0.value < $1.value }?.key ?? .other
    }
}

enum TimeRange: String, CaseIterable, Identifiable {
    case day = "1D", week = "7D", month = "1M", year = "1Y"

    var id: String { rawValue }

    var longName: String {
        switch self {
        case .day: "day"
        case .week: "week"
        case .month: "month"
        case .year: "year"
        }
    }

    var bucketUnit: Calendar.Component {
        switch self {
        case .day: .hour
        case .week, .month: .day
        case .year: .month
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .day: .dateTime.hour()
        case .week: .dateTime.weekday(.abbreviated)
        case .month: .dateTime.day().month(.abbreviated)
        case .year: .dateTime.month(.abbreviated)
        }
    }

    var pointFormat: Date.FormatStyle {
        switch self {
        case .day: .dateTime.weekday(.abbreviated).hour().minute()
        case .week, .month: .dateTime.weekday(.wide).day().month(.abbreviated)
        case .year: .dateTime.month(.wide).year()
        }
    }

    /// What the period is called when it's the current one: "Last 24 hours", "This month".
    var currentName: String {
        switch self {
        case .day: "Today"
        case .week: "This week"
        case .month: "This month"
        case .year: "This year"
        }
    }

    /// The calendar day, the Sunday-to-Saturday week, the calendar month or the calendar year
    /// holding `now`, from start to end, even when part of it hasn't happened yet.
    func interval(endingAt now: Date, calendar: Calendar = .app) -> DateInterval {
        switch self {
        case .day:
            return calendar.dateInterval(of: .day, for: now)!
        case .week:
            return TimeRange.sundayWeek(holding: now, calendar: calendar)
        case .month:
            return calendar.dateInterval(of: .month, for: now)!
        case .year:
            return calendar.dateInterval(of: .year, for: now)!
        }
    }

    /// The Sunday-to-Saturday week holding `date`, whatever day the calendar starts its weeks on.
    static func sundayWeek(holding date: Date, calendar: Calendar = .app) -> DateInterval {
        let day = calendar.startOfDay(for: date)
        let back = calendar.component(.weekday, from: day) - 1   // weekday 1 is Sunday
        let start = calendar.date(byAdding: .day, value: -back, to: day)!
        return DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!)
    }

    /// A moment inside the period `offset` pages back: 0 is now, −1 one page earlier.
    /// Pages move by whole days, weeks, months and years, so they tile.
    func anchor(offset: Int, now: Date, calendar: Calendar = .app) -> Date {
        guard offset != 0 else { return now }
        return switch self {
        case .day: calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
        case .week: calendar.date(byAdding: .day, value: 7 * offset, to: TimeRange.sundayWeek(holding: now, calendar: calendar).start)!
        case .month: calendar.date(byAdding: .month, value: offset, to: calendar.dateInterval(of: .month, for: now)!.start)!
        case .year: calendar.date(byAdding: .year, value: offset, to: calendar.dateInterval(of: .year, for: now)!.start)!
        }
    }

    /// The period shown at `offset`.
    func interval(offset: Int, now: Date, calendar: Calendar = .app) -> DateInterval {
        interval(endingAt: anchor(offset: offset, now: now, calendar: calendar), calendar: calendar)
    }

    /// The page the period holding `date` is on: 0 for the one holding `now`, −1 the one before.
    /// Picking a date in the calendar jumps here.
    func offset(of date: Date, now: Date, calendar: Calendar = .app) -> Int {
        let picked = interval(endingAt: date, calendar: calendar).start
        let current = interval(endingAt: now, calendar: calendar).start
        return switch self {
        case .day: calendar.dateComponents([.day], from: current, to: picked).day!
        case .week: Int((Double(calendar.dateComponents([.day], from: current, to: picked).day!) / 7).rounded())
        case .month: calendar.dateComponents([.month], from: current, to: picked).month!
        case .year: calendar.dateComponents([.year], from: current, to: picked).year!
        }
    }

    /// What the period at `offset` is compared with. A period still under way is compared with the
    /// same stretch of the one before (1–18 Oct with 1–18 Sep, today until 14:00 with yesterday
    /// until 14:00); a finished one with the whole period before.
    func comparison(offset: Int, now: Date, calendar: Calendar = .app) -> DateInterval {
        let previous = interval(offset: offset - 1, now: now, calendar: calendar)
        let current = interval(offset: offset, now: now, calendar: calendar)
        guard current.contains(now) else { return previous }
        let cut = self == .day
            ? calendar.dateInterval(of: .hour, for: now)!.end
            : calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let shifted = switch self {
        case .day: calendar.date(byAdding: .day, value: -1, to: cut)!
        case .week: calendar.date(byAdding: .day, value: -7, to: cut)!
        case .month: calendar.date(byAdding: .month, value: -1, to: cut)!
        case .year: calendar.date(byAdding: .year, value: -1, to: cut)!
        }
        return DateInterval(start: previous.start, end: min(max(shifted, previous.start), previous.end))
    }

    /// "1–18 Sep", "1 Jan – 18 Oct 2025" or "September 2026": what a comparison covers.
    func comparisonLabel(_ interval: DateInterval, calendar: Calendar = .app) -> String {
        let last = interval.end.addingTimeInterval(-1)
        switch self {
        case .month:
            if calendar.isDate(interval.end, equalTo: calendar.dateInterval(of: .month, for: interval.start)!.end, toGranularity: .day)
                && calendar.component(.day, from: interval.end) == 1 {
                return interval.start.formatted(.dateTime.month(.wide).year())
            }
            return "\(calendar.component(.day, from: interval.start))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
        case .year:
            if calendar.dateInterval(of: .year, for: interval.start)!.end == interval.end {
                return interval.start.formatted(.dateTime.year())
            }
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .day:
            let day = interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            return calendar.dateInterval(of: .day, for: interval.start)!.end == interval.end
                ? day : "\(day) to \(interval.end.formatted(.dateTime.hour().minute()))"
        case .week:
            if calendar.isDate(interval.start, inSameDayAs: last) {
                return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            }
            return "\(calendar.component(.day, from: interval.start))–\(last.formatted(.dateTime.day().month(.abbreviated)))"
        }
    }

    /// One chart bucket: the hour, day or month starting at `start`.
    func bucket(startingAt start: Date, calendar: Calendar = .app) -> DateInterval {
        DateInterval(start: start, end: calendar.date(byAdding: bucketUnit, value: 1, to: start)!)
    }

    /// "18 Sep – 17 Oct 2026", "October 2026" or "2026": what the period covers.
    func label(for interval: DateInterval) -> String {
        let last = interval.end.addingTimeInterval(-1)
        switch self {
        case .day:
            return interval.start.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated).year())
        case .week:
            return "\(interval.start.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated).year()))"
        case .month:
            return interval.start.formatted(.dateTime.month(.wide).year())
        case .year:
            return interval.start.formatted(.dateTime.year())
        }
    }
}

struct SpendPoint: Identifiable {
    let date: Date
    /// Spent in this bucket. A candle closes here.
    let amount: Double
    let cumulative: Double
    /// Spent in the bucket before (the period before, for the first one). A candle opens here,
    /// so candles, bars, the average line and the last-value tag all share one scale.
    let open: Double
    /// The smallest and biggest single receipt in the bucket, for the crosshair readout.
    let low: Double
    let high: Double
    /// True when this bucket cost more than the one before.
    let rose: Bool
    let count: Int

    var id: Date { date }
    var close: Double { amount }
    /// Nothing spent in this bucket or the one before: no candle to draw.
    var isEmptyCandle: Bool { open == 0 && close == 0 }
    /// Spent exactly the same as the bucket before.
    var isFlat: Bool { open == close }

    init(date: Date, amount: Double, cumulative: Double, open: Double = 0, low: Double = 0, high: Double = 0, rose: Bool = false, count: Int) {
        self.date = date
        self.amount = amount
        self.cumulative = cumulative
        self.open = open
        self.low = low
        self.high = high
        self.rose = rose
        self.count = count
    }
}

struct CategoryAmount: Identifiable {
    let category: SpendCategory
    let amount: Double
    var id: SpendCategory { category }
}

struct MonthAmount: Identifiable {
    let month: Date
    let amount: Double
    var id: Date { month }
}

struct DaySpend: Identifiable {
    let day: Date
    let total: Double
    let topShop: String
    var id: Date { day }
}

struct DayTotal: Identifiable, Equatable {
    let day: Date
    let total: Double
    let count: Int
    var id: Date { day }
}

struct WeekSpend {
    let start: Date
    let total: Double
    let usual: Double
    let topCategory: SpendCategory
}

struct WeekdayAmount: Identifiable {
    let weekday: Int
    let name: String
    let average: Double
    var id: Int { weekday }
}

struct CategoryTrend: Identifiable {
    let category: SpendCategory
    let recent: Double
    let usual: Double
    var id: SpendCategory { category }
    var change: Double? { usual > 0 ? (recent - usual) / usual : nil }
}

struct Forecast {
    let month: Date
    let predicted: Double
    let low: Double
    let high: Double
    let history: [MonthAmount]
    let spentThisMonth: Double
    let thisMonthPace: Double
}

struct BillMonth: Identifiable {
    let month: Date
    let kind: ReceiptKind
    let amount: Double
    let units: Double
    var id: String { "\(month.timeIntervalSince1970)-\(kind.rawValue)" }
}

struct BillSummary {
    let year: Int
    let totalSpending: Double
    let byKind: [ReceiptKind: Double]
    let months: [BillMonth]

    var billsTotal: Double { byKind.values.reduce(0, +) }
    var billsShare: Double { totalSpending > 0 ? billsTotal / totalSpending : 0 }
    func amount(_ kind: ReceiptKind) -> Double { byKind[kind] ?? 0 }
    func share(_ kind: ReceiptKind) -> Double { totalSpending > 0 ? amount(kind) / totalSpending : 0 }
    var peakElectricity: BillMonth? {
        months.filter { $0.kind == .electricity }.max { $0.amount < $1.amount }
    }
}

/// Finds spending patterns: totals over time, big moments, trends and a simple forecast.
struct SpendingAnalyzer {
    /// Single purchases above this are treated as one-offs when forecasting.
    static let oneOffThreshold = 10_000.0

    let receipts: [ReceiptSnapshot]
    let calendar: Calendar

    init(_ receipts: [ReceiptSnapshot], calendar: Calendar = .app) {
        self.receipts = receipts.sorted { $0.date < $1.date }
        self.calendar = calendar
    }

    func receipts(in interval: DateInterval) -> [ReceiptSnapshot] {
        receipts.filter { $0.date >= interval.start && $0.date < interval.end }
    }

    func total(in interval: DateInterval) -> Double {
        receipts(in: interval).reduce(0) { $0 + $1.total }
    }

    var years: [Int] {
        Array(Set(receipts.map { calendar.component(.year, from: $0.date) })).sorted()
    }

    // MARK: - Chart

    /// The earliest page that holds a receipt (0 when there are none, or none before this period).
    func earliestOffset(for range: TimeRange, now: Date) -> Int {
        guard let first = receipts.first?.date else { return 0 }
        var offset = 0
        // Bounded so a receipt dated far in the past can't hang the app.
        while offset > -2_000, range.interval(offset: offset, now: now, calendar: calendar).start > first {
            offset -= 1
        }
        return offset
    }

    /// Chart points for the period `offset` windows back from now. Each point's candle opens at the
    /// bucket before's spending and closes at this bucket's, like a price moving from one day to the next.
    func points(for range: TimeRange, now: Date, offset: Int = 0) -> [SpendPoint] {
        let interval = range.interval(offset: offset, now: now, calendar: calendar)
        let inRange = receipts(in: interval)
        let before = calendar.date(byAdding: range.bucketUnit, value: -1, to: interval.start)!
        var previous = total(in: DateInterval(start: before, end: interval.start))
        var points: [SpendPoint] = []
        var running = 0.0
        var start = interval.start
        // Buckets still to come are left out, so the chart stops at today and the rest stays empty.
        while start < interval.end, start <= now {
            let end = calendar.date(byAdding: range.bucketUnit, value: 1, to: start)!
            let bucket = inRange.filter { $0.date >= start && $0.date < end }
            let amount = bucket.reduce(0) { $0 + $1.total }
            running += amount
            let sizes = bucket.map(\.total)
            points.append(SpendPoint(
                date: start,
                amount: amount,
                cumulative: running,
                open: previous,
                low: sizes.min() ?? 0,
                high: sizes.max() ?? 0,
                rose: amount > previous,
                count: bucket.count
            ))
            previous = amount
            start = end
        }
        return points
    }

    func categoryTotals(in interval: DateInterval) -> [CategoryAmount] {
        var totals: [SpendCategory: Double] = [:]
        for receipt in receipts(in: interval) {
            for (category, amount) in receipt.categoryAmounts { totals[category, default: 0] += amount }
        }
        return totals
            .map { CategoryAmount(category: $0.key, amount: $0.value) }
            .filter { $0.amount > 0 }
            .sorted { $0.amount > $1.amount }
    }

    // MARK: - One category, indicators

    /// The same receipts counted only for what they spent on one category, so every chart and total
    /// works for a single category exactly as it does for all spending.
    func only(_ category: SpendCategory) -> SpendingAnalyzer {
        SpendingAnalyzer(receipts.compactMap { receipt in
            guard let amount = receipt.categoryAmounts[category], amount > 0.005 else { return nil }
            return ReceiptSnapshot(id: receipt.id, date: receipt.date, total: amount, shop: receipt.shop,
                                   kind: receipt.kind, items: [(category, amount)])
        }, calendar: calendar)
    }

    /// Only receipts of one type: purchases, or one kind of bill.
    func only(kind: ReceiptKind) -> SpendingAnalyzer {
        SpendingAnalyzer(receipts.filter { $0.kind == kind }, calendar: calendar)
    }

    /// A trailing average of each bucket's spending over `window` buckets, using the period before
    /// so the first buckets have a full window too. One value per point of `points`.
    static func movingAverage(of points: [SpendPoint], previous: [SpendPoint], window: Int) -> [Double] {
        let amounts = previous.map(\.amount) + points.map(\.amount)
        let offset = previous.count
        return points.indices.map { i in
            let end = offset + i
            let start = max(0, end - window + 1)
            let slice = amounts[start...end]
            return slice.reduce(0, +) / Double(slice.count)
        }
    }

    // MARK: - Calendar

    /// Spending per day in `interval`, purchases and bills alike, keyed by the start of each day.
    /// Days with nothing spent are left out. Uses the same calendar as every other screen.
    func dailyTotals(in interval: DateInterval) -> [Date: DayTotal] {
        var totals: [Date: DayTotal] = [:]
        for receipt in receipts(in: interval) {
            let day = calendar.startOfDay(for: receipt.date)
            let current = totals[day] ?? DayTotal(day: day, total: 0, count: 0)
            totals[day] = DayTotal(day: day, total: current.total + receipt.total, count: current.count + 1)
        }
        return totals
    }

    /// The month holding `date`, as the calendar shows it.
    func month(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .month, for: date)!
    }

    func day(containing date: Date) -> DateInterval {
        calendar.dateInterval(of: .day, for: date)!
    }

    // MARK: - What cost so much, and when

    /// Daily purchase totals (bills excluded) for the last `days` days, including days with nothing spent.
    func dailyPurchases(days: Int, now: Date) -> [DaySpend] {
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: -(days - 1), to: today)!
        let purchases = receipts.filter { !$0.kind.isBill && $0.date >= start }
        let grouped = Dictionary(grouping: purchases) { calendar.startOfDay(for: $0.date) }
        return (0..<days).map { offset in
            let day = calendar.date(byAdding: .day, value: offset, to: start)!
            let dayReceipts = grouped[day] ?? []
            let top = dayReceipts.max { $0.total < $1.total }
            return DaySpend(day: day, total: dayReceipts.reduce(0) { $0 + $1.total }, topShop: top?.shop ?? "")
        }
    }

    /// Days that cost far more than usual: above the average by two standard deviations.
    func spikeDays(now: Date, days: Int = 90) -> [DaySpend] {
        let series = dailyPurchases(days: days, now: now)
        let values = series.map(\.total)
        guard values.count > 7 else { return [] }
        let mean = values.reduce(0, +) / Double(values.count)
        let variance = values.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(values.count)
        let threshold = mean + 2 * variance.squareRoot()
        return series.filter { $0.total > threshold && $0.total > 0 }
            .sorted { $0.total > $1.total }
            .prefix(3)
            .map { $0 }
    }

    func biggestReceipts(now: Date, days: Int = 90, count: Int = 3) -> [ReceiptSnapshot] {
        let start = now.addingTimeInterval(-Double(days) * 86_400)
        return receipts.filter { $0.date >= start && !$0.kind.isBill }
            .sorted { $0.total > $1.total }
            .prefix(count)
            .map { $0 }
    }

    func biggestWeek(now: Date, weeks: Int = 13) -> WeekSpend? {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return nil }
        let starts = (0..<weeks).compactMap { calendar.date(byAdding: .weekOfYear, value: -$0, to: thisWeek) }
        let totals = starts.map { start -> (Date, Double, [ReceiptSnapshot]) in
            let inside = receipts(in: DateInterval(start: start, end: calendar.date(byAdding: .day, value: 7, to: start)!))
            return (start, inside.reduce(0) { $0 + $1.total }, inside)
        }
        guard let best = totals.max(by: { $0.1 < $1.1 }), best.1 > 0 else { return nil }
        let others = totals.filter { $0.0 != best.0 && $0.1 > 0 }
        let usual = others.isEmpty ? 0 : others.map(\.1).reduce(0, +) / Double(others.count)
        var byCategory: [SpendCategory: Double] = [:]
        for receipt in best.2 {
            for (category, amount) in receipt.categoryAmounts { byCategory[category, default: 0] += amount }
        }
        let top = byCategory.max { $0.value < $1.value }?.key ?? .other
        return WeekSpend(start: best.0, total: best.1, usual: usual, topCategory: top)
    }

    /// Average purchase spending on each weekday over the last 12 weeks, Monday first.
    func weekdayAverages(now: Date, weeks: Int = 12) -> [WeekdayAmount] {
        let series = dailyPurchases(days: weeks * 7, now: now)
        var sums: [Int: Double] = [:]
        var counts: [Int: Int] = [:]
        for day in series {
            let weekday = calendar.component(.weekday, from: day.day)
            sums[weekday, default: 0] += day.total
            counts[weekday, default: 0] += 1
        }
        let symbols = calendar.shortWeekdaySymbols
        return [2, 3, 4, 5, 6, 7, 1].map { weekday in
            WeekdayAmount(
                weekday: weekday,
                name: symbols[weekday - 1],
                average: (sums[weekday] ?? 0) / Double(max(1, counts[weekday] ?? 0))
            )
        }
    }

    /// This month so far by category, compared with the same days of the three months before,
    /// on the same calendar month as Overview's 1M, so the totals on both screens agree.
    func categoryTrends(now: Date) -> [CategoryTrend] {
        let month = TimeRange.month.interval(endingAt: now, calendar: calendar)
        let soFar = DateInterval(start: month.start, end: min(month.end, calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!))
        let recent = Dictionary(uniqueKeysWithValues: categoryTotals(in: soFar).map { ($0.category, $0.amount) })
        var before: [SpendCategory: Double] = [:]
        for back in 1...3 {
            let start = calendar.date(byAdding: .month, value: -back, to: month.start)!
            let monthEnd = calendar.dateInterval(of: .month, for: start)!.end
            let end = min(calendar.date(byAdding: .month, value: -back, to: soFar.end)!, monthEnd)
            for item in categoryTotals(in: DateInterval(start: start, end: max(end, start))) { before[item.category, default: 0] += item.amount / 3 }
        }
        let hasHistory = receipts.first.map { $0.date < calendar.date(byAdding: .month, value: -1, to: month.start)! } ?? false
        guard hasHistory else { return [] }
        return Set(recent.keys).union(before.keys)
            .map { CategoryTrend(category: $0, recent: recent[$0] ?? 0, usual: before[$0] ?? 0) }
            .filter { $0.recent > 0 || $0.usual > 0 }
            .sorted { abs($0.recent - $0.usual) > abs($1.recent - $1.usual) }
    }

    // MARK: - Forecast

    /// Next month's spending: a straight-line trend through the last six complete months,
    /// nudged by how fast this month is going. One-off purchases over ฿10,000 are left out.
    func forecast(now: Date) -> Forecast? {
        let regular = receipts.filter { $0.total < Self.oneOffThreshold || $0.kind.isBill }
        guard let first = regular.first?.date,
              let thisMonth = calendar.dateInterval(of: .month, for: now) else { return nil }

        func spent(_ interval: DateInterval) -> Double {
            regular.filter { $0.date >= interval.start && $0.date < interval.end }.reduce(0) { $0 + $1.total }
        }

        let firstMonth = calendar.dateInterval(of: .month, for: first)!
        var cursor = first <= firstMonth.start.addingTimeInterval(2 * 86_400) ? firstMonth.start : firstMonth.end
        var history: [MonthAmount] = []
        while cursor < thisMonth.start {
            let next = calendar.date(byAdding: .month, value: 1, to: cursor)!
            history.append(MonthAmount(month: cursor, amount: spent(DateInterval(start: cursor, end: next))))
            cursor = next
        }
        history = Array(history.suffix(6))

        let spentSoFar = spent(DateInterval(start: thisMonth.start, end: now))
        let daysElapsed = max(1, now.timeIntervalSince(thisMonth.start) / 86_400)
        let daysInMonth = thisMonth.duration / 86_400
        let pace = spentSoFar / daysElapsed * daysInMonth
        let monthWeight = 0.3 * min(1, daysElapsed / daysInMonth)

        guard history.count >= 2 else {
            guard spentSoFar > 0 || !history.isEmpty else { return nil }
            let guess = history.last?.amount ?? pace
            return Forecast(month: thisMonth.end, predicted: guess, low: guess * 0.85, high: guess * 1.15,
                            history: history, spentThisMonth: spentSoFar, thisMonthPace: pace)
        }

        let n = Double(history.count)
        let xs = (0..<history.count).map(Double.init)
        let ys = history.map(\.amount)
        let meanX = xs.reduce(0, +) / n
        let meanY = ys.reduce(0, +) / n
        let sxx = xs.map { ($0 - meanX) * ($0 - meanX) }.reduce(0, +)
        let sxy = zip(xs, ys).map { ($0 - meanX) * ($1 - meanY) }.reduce(0, +)
        let slope = sxx > 0 ? sxy / sxx : 0
        let intercept = meanY - slope * meanX
        // History is months 0…n-1, this month is n, next month is n+1.
        let trend = intercept + slope * (n + 1)
        let residuals = zip(xs, ys).map { $1 - (intercept + slope * $0) }
        let spread = (residuals.map { $0 * $0 }.reduce(0, +) / max(1, n - 2)).squareRoot()

        let predicted = max(0, (1 - monthWeight) * trend + monthWeight * pace)
        let margin = max(spread, predicted * 0.05)
        return Forecast(month: thisMonth.end, predicted: predicted, low: max(0, predicted - margin), high: predicted + margin,
                        history: history, spentThisMonth: spentSoFar, thisMonthPace: pace)
    }

    // MARK: - Bills

    func billSummary(year: Int) -> BillSummary {
        let yearReceipts = receipts.filter { calendar.component(.year, from: $0.date) == year }
        let bills = yearReceipts.filter { $0.kind.isBill }
        var byKind: [ReceiptKind: Double] = [:]
        var monthly: [String: (month: Date, kind: ReceiptKind, amount: Double, units: Double)] = [:]
        for bill in bills {
            byKind[bill.kind, default: 0] += bill.total
            let month = calendar.dateInterval(of: .month, for: bill.date)!.start
            let key = "\(month.timeIntervalSince1970)-\(bill.kind.rawValue)"
            var entry = monthly[key] ?? (month: month, kind: bill.kind, amount: 0, units: 0)
            entry.amount += bill.total
            entry.units += bill.billUnits
            monthly[key] = entry
        }
        let months = monthly.values
            .map { BillMonth(month: $0.month, kind: $0.kind, amount: $0.amount, units: $0.units) }
            .sorted { $0.month < $1.month }
        return BillSummary(year: year, totalSpending: yearReceipts.reduce(0) { $0 + $1.total }, byKind: byKind, months: months)
    }

    // MARK: - Facts for the AI summary

    func facts(now: Date) -> [String] {
        var facts: [String] = []
        // The same calendar month as Overview's 1M, so far.
        let last30 = TimeRange.month.interval(endingAt: now, calendar: calendar)
        let spent30 = total(in: last30)
        guard spent30 > 0 else { return [] }
        let monthName = now.formatted(.dateTime.month(.wide))

        if let forecast = self.forecast(now: now), let usual = forecast.history.isEmpty ? nil : forecast.history.map(\.amount).reduce(0, +) / Double(forecast.history.count), usual > 0 {
            facts.append("Spent \(spent30.bahtWhole) so far in \(monthName); a usual whole month is \(usual.bahtWhole).")
            facts.append("Forecast for next month: about \(forecast.predicted.bahtWhole).")
        } else {
            facts.append("Spent \(spent30.bahtWhole) so far in \(monthName).")
        }

        let categories = categoryTotals(in: last30)
        if let top = categories.first {
            facts.append("Biggest category so far this month: \(top.category.name), \(top.amount.bahtWhole) (\((top.amount / spent30).percent)).")
        }
        let weekdays = weekdayAverages(now: now)
        if let peak = weekdays.max(by: { $0.average < $1.average }) {
            let others = weekdays.filter { $0.weekday != peak.weekday }.map(\.average)
            let usual = others.reduce(0, +) / Double(max(1, others.count))
            if usual > 0, peak.average > usual * 1.3 {
                facts.append("\(peak.name) is the most expensive day: \(peak.average.bahtWhole) on average versus \(usual.bahtWhole) on other days.")
            }
        }
        if let week = biggestWeek(now: now), week.usual > 0, week.total > week.usual * 1.3 {
            let end = calendar.date(byAdding: .day, value: 6, to: week.start)!
            facts.append("Most expensive week: \(week.start.formatted(.dateTime.day().month(.abbreviated)))–\(end.formatted(.dateTime.day().month(.abbreviated))), \(week.total.bahtWhole), mostly \(week.topCategory.name).")
        }
        if let biggest = biggestReceipts(now: now, count: 1).first {
            facts.append("Largest single purchase: \(biggest.shop), \(biggest.total.bahtWhole) on \(biggest.date.formatted(.dateTime.day().month(.abbreviated))).")
        }
        for trend in categoryTrends(now: now).prefix(2) {
            if let change = trend.change, abs(change) >= 0.25, trend.recent > 500 {
                facts.append("\(trend.category.name) is \(change > 0 ? "up" : "down") \(abs(change).percent) compared with usual (\(trend.recent.bahtWhole) vs \(trend.usual.bahtWhole)).")
            }
        }
        let bills = billSummary(year: now.year)
        if bills.amount(.electricity) > 0 {
            facts.append("Electricity cost \(bills.amount(.electricity).bahtWhole) so far this year, \(bills.share(.electricity).percent) of all spending.")
        }
        return facts
    }
}
