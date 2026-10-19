import Charts
import SwiftData
import SwiftUI

/// Data analysis: insights, tax and the receipt graph.
struct PlanView: View {
    enum Page: String, CaseIterable, Identifiable {
        case insights = "Insights"
        case tax = "Tax"
        case graph = "Graph"
        var id: String { rawValue }
    }

    @State private var page: Page = LaunchOption.string("page").flatMap { Page(rawValue: $0.capitalized) } ?? .insights
    @Environment(AppRouter.self) private var router

    var body: some View {
        VStack(spacing: 0) {
            SegmentedBar(title: "Page", options: Page.allCases, selection: $page) { $0.rawValue }
                .padding(.horizontal)
                .padding(.vertical, 8)

            switch page {
            case .insights: InsightsView()
            case .tax: TaxView()
            case .graph: SpendingGraphView(center: router.graphCenter).id(router.graphCenter ?? "global")
            }
        }
        .background(Theme.paper)
        .navigationTitle("Data analysis")
        .onChange(of: router.graphCenter, initial: true) { _, centre in
            if centre != nil { page = .graph }
        }
    }
}

struct InsightsView: View {
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    @State private var summary: SpendingSummary?
    @Environment(\.pageAccent) private var accent

    var body: some View {
        let analyzer = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let now = Date.now
        let forecast = analyzer.forecast(now: now)
        let week = analyzer.biggestWeek(now: now)
        let biggest = analyzer.biggestReceipts(now: now)
        let spikes = analyzer.spikeDays(now: now)
        let weekdays = analyzer.weekdayAverages(now: now)
        let trends = analyzer.categoryTrends(now: now)

        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                summaryCard

                if let forecast { ForecastCard(forecast: forecast) }

                Card(title: "What cost so much, and when", subtitle: "Last 90 days", color: .coral) {
                    VStack(alignment: .leading, spacing: 12) {
                        if let week {
                            let end = Calendar.app.date(byAdding: .day, value: 6, to: week.start)!
                            AdaptiveStack(spacing: 10) {
                                CategoryIcon(symbol: "calendar", size: 34, fill: accent)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Most expensive week").font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text("\(week.start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated))): \(week.total.bahtWhole), mostly \(week.topCategory.name)")
                                        .font(.subheadline)
                                        .foregroundStyle(Theme.ink)
                                    if week.usual > 0 {
                                        Text("A usual week is \(week.usual.bahtWhole)").font(.footnote).foregroundStyle(Theme.muted)
                                    }
                                }
                            }
                            .accessibilityElement(children: .combine)
                        }
                        ForEach(Array(biggest.enumerated()), id: \.offset) { _, receipt in
                            AdaptiveStack(spacing: 10) {
                                CategoryIcon(symbol: receipt.mainCategory.symbol, size: 34, fill: receipt.mainCategory.color)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(receipt.shop).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                    Text(receipt.date, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                        .font(.footnote).foregroundStyle(Theme.muted)
                                }
                                Spacer(minLength: 8)
                                Text(receipt.total.bahtWhole).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                            }
                            .accessibilityElement(children: .combine)
                        }
                        if !spikes.isEmpty {
                            Divider()
                            Text("Days far above your normal").font(Theme.label).foregroundStyle(Theme.ink)
                            ForEach(spikes) { day in
                                AdaptiveStack(spacing: 8) {
                                    Text(day.day, format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                                        .foregroundStyle(Theme.ink)
                                    Text(day.topShop).foregroundStyle(Theme.muted).lineLimit(1)
                                    Spacer(minLength: 8)
                                    Text(day.total.bahtWhole).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                                }
                                .font(.subheadline)
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }

                Card(title: "Your spending week", subtitle: "Average per weekday, last 12 weeks, bills left out", color: .sky) {
                    let peak = weekdays.max { $0.average < $1.average }
                    Chart(weekdays) { day in
                        let isPeak = day.weekday == peak?.weekday
                        BarMark(x: .value("Day", day.name), y: .value("Average", day.average))
                            .foregroundStyle(isPeak ? Theme.ink : Theme.quiet)
                            .annotation(position: .top) {
                                if isPeak {
                                    Text("PEAK").font(Theme.smallLabel).foregroundStyle(Theme.ink)
                                }
                            }
                    }
                    .chartYAxis {
                        AxisMarks { value in
                            AxisGridLine().foregroundStyle(Theme.quiet.opacity(0.5))
                            AxisValueLabel { if let amount = value.as(Double.self) { Text(amount.bahtCompact) } }
                        }
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    .frame(height: 240)
                }

                if !trends.isEmpty {
                    Card(title: "Compared with usual", subtitle: "This month so far against the same days of the three months before", color: .orange) {
                        VStack(spacing: 10) {
                            ForEach(trends.prefix(6)) { trend in
                                AdaptiveStack(spacing: 10) {
                                    CategoryIcon(symbol: trend.category.symbol, size: 32, fill: trend.category.color)
                                    Text(trend.category.name).font(.subheadline).foregroundStyle(Theme.ink)
                                    Spacer(minLength: 8)
                                    Text(trend.recent.bahtWhole).font(Theme.figure(.subheadline)).foregroundStyle(Theme.ink)
                                    if let change = trend.change {
                                        Text("\(change >= 0 ? "▲" : "▼") \(abs(change).percent)")
                                            .font(Theme.figure(.subheadline))
                                            .foregroundStyle(change >= 0 ? Theme.up : Theme.down)
                                            .frame(minWidth: 64, alignment: .trailing)
                                            .accessibilityLabel("\(abs(change).percent) \(change >= 0 ? "more" : "less") than usual")
                                    } else {
                                        Text("NEW").font(Theme.smallLabel).foregroundStyle(Theme.muted).frame(minWidth: 64, alignment: .trailing)
                                    }
                                }
                                .accessibilityElement(children: .combine)
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.paper)
        .task(id: receipts.count) {
            summary = await InsightWriter.summary(facts: analyzer.facts(now: .now))
        }
    }

    private var summaryCard: some View {
        Card(title: "This month in a sentence", subtitle: summary?.writtenByAI == true ? "Written by Apple Intelligence on this device" : "From your spending numbers", color: .purple) {
            if let summary {
                VStack(alignment: .leading, spacing: 10) {
                    Text(summary.headline).font(.title3.weight(.bold)).foregroundStyle(Theme.ink)
                    ForEach(summary.tips, id: \.self) { tip in
                        Label(tip, systemImage: "arrow.right.square.fill")
                            .font(.subheadline)
                            .foregroundStyle(Theme.ink)
                    }
                }
            } else {
                HStack(spacing: 10) {
                    ProgressView().tint(Theme.ink)
                    Text("Looking at your spending…").foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

struct ForecastCard: View {
    let forecast: Forecast

    var body: some View {
        Card(title: "Next month", subtitle: "Trend from your last \(forecast.history.count) months, one-off buys over ฿10,000 left out", color: .lime) {
            VStack(alignment: .leading, spacing: 4) {
                HeroFigure(text: "≈ \(forecast.predicted.bahtWhole)")
                Text("Likely between \(forecast.low.bahtWhole) and \(forecast.high.bahtWhole) in \(forecast.month.formatted(.dateTime.month(.wide)))")
                    .font(.subheadline).foregroundStyle(Theme.muted)
                if forecast.spentThisMonth > 0 {
                    Text("This month so far: \(forecast.spentThisMonth.bahtWhole), on pace for \(forecast.thisMonthPace.bahtWhole)")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
            }
            .accessibilityElement(children: .combine)
            Chart {
                ForEach(forecast.history) { month in
                    BarMark(x: .value("Month", month.month, unit: .month), y: .value("Spent", month.amount))
                        .foregroundStyle(Theme.ink)
                }
                BarMark(x: .value("Month", forecast.month, unit: .month), y: .value("Spent", forecast.predicted))
                    .foregroundStyle(Theme.quiet)
                    .annotation(position: .top) {
                        Text("NEXT").font(Theme.smallLabel).foregroundStyle(Theme.ink)
                    }
                RuleMark(x: .value("Month", forecast.month, unit: .month),
                         yStart: .value("Low", forecast.low), yEnd: .value("High", forecast.high))
                    .foregroundStyle(Theme.ink)
                    .lineStyle(StrokeStyle(lineWidth: 3))
            }
            .chartXAxis {
                AxisMarks(values: .stride(by: .month)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated))
                }
            }
            .chartYAxis {
                AxisMarks { value in
                    AxisGridLine().foregroundStyle(Theme.quiet.opacity(0.5))
                    AxisValueLabel { if let amount = value.as(Double.self) { Text(amount.bahtCompact) } }
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .frame(height: 230)
        }
    }
}
