import Charts
import SwiftData
import SwiftUI

struct BillsView: View {
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    @State private var year = Date.now.year

    var body: some View {
        let analyzer = SpendingAnalyzer(receipts.map(ReceiptSnapshot.init))
        let summary = analyzer.billSummary(year: year)
        let years = analyzer.years
        let billReceipts = receipts.filter { $0.kind.isBill && $0.date.year == year }.reversed()

        ScrollView {
            VStack(spacing: 16) {
                if years.count > 1 {
                    SegmentedBar(title: "Year", options: years, selection: $year, tint: { Theme.rainbow[abs($0) % Theme.rainbow.count] }) { String($0) }
                }

                Card(title: "Bills in \(String(year))", subtitle: "Electricity, water and internet as a share of everything you spent", color: .sky) {
                    VStack(alignment: .leading, spacing: 6) {
                        HeroFigure(text: summary.billsTotal.baht, highlighted: true)
                        Text("\(summary.billsShare.percent) of \(summary.totalSpending.bahtWhole) spent this year")
                            .font(.subheadline).foregroundStyle(Theme.muted)
                    }
                    .accessibilityElement(children: .combine)
                    AdaptiveStack(spacing: 10, alignment: .top) {
                        ForEach(ReceiptKind.billKinds) { kind in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    CategoryIcon(symbol: kind.symbol, size: 32, fill: kind.fill)
                                    // The colour this bill has in the chart below.
                                    RoundedRectangle(cornerRadius: 4).fill(kind.color).frame(width: 16, height: 16)
                                        .accessibilityHidden(true)
                                }
                                Text(kind.name).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.ink)
                                // One line, shrinking to fit the narrow tile rather than breaking the number.
                                Text(summary.amount(kind).bahtWhole)
                                    .font(Theme.figure(.title3))
                                    .foregroundStyle(Theme.ink)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.5)
                                Text("\(summary.share(kind).percent) of all spending").font(.footnote).foregroundStyle(Theme.muted)
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            .padding(12)
                            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.line, lineWidth: 1))
                            .accessibilityElement(children: .combine)
                        }
                    }
                    // Same height for all three tiles.
                    .fixedSize(horizontal: false, vertical: true)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 16, alignment: .top)], alignment: .leading, spacing: 16) {
                    Card(title: "Month by month", color: .mint) {
                        if summary.months.isEmpty {
                            ContentUnavailableView("No bills this year", systemImage: "bolt.slash")
                        } else {
                            // Same stacking order every month: electricity at the bottom, then water, then internet.
                            Chart(summary.months.sorted { ($0.month, $0.kind.stackOrder) < ($1.month, $1.kind.stackOrder) }) { month in
                                BarMark(x: .value("Month", month.month, unit: .month), y: .value("Amount", month.amount))
                                    .foregroundStyle(by: .value("Bill", month.kind.name))
                            }
                            .chartForegroundStyleScale([
                                ReceiptKind.electricity.name: ReceiptKind.electricity.color,
                                ReceiptKind.water.name: ReceiptKind.water.color,
                                ReceiptKind.internet.name: ReceiptKind.internet.color,
                            ])
                            .chartLegend(position: .bottom, alignment: .leading, spacing: 12)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisValueLabel(format: .dateTime.month(.narrow)).font(Theme.smallLabel)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { value in
                                    AxisGridLine().foregroundStyle(Theme.quiet.opacity(0.5))
                                    AxisValueLabel { if let amount = value.as(Double.self) { Text(amount.bahtCompact) } }
                                        .font(Theme.smallLabel)
                                }
                            }
                            .frame(height: 280)
                        }
                    }

                    let electricity = summary.months.filter { $0.kind == .electricity && $0.units > 0 }
                    Card(title: "Electricity use", subtitle: "Units (kWh) from your electricity bills", color: .yellow) {
                        if electricity.isEmpty {
                            ContentUnavailableView("No electricity bills", systemImage: "bolt.slash")
                        } else {
                            Chart(electricity) { month in
                                LineMark(x: .value("Month", month.month, unit: .month), y: .value("kWh", month.units))
                                    .foregroundStyle(Theme.ink)
                                    .lineStyle(StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                                PointMark(x: .value("Month", month.month, unit: .month), y: .value("kWh", month.units))
                                    .symbol(.circle)
                                    .symbolSize(80)
                                    .foregroundStyle(Theme.ink)
                            }
                            .chartXAxis {
                                AxisMarks(values: .stride(by: .month)) { _ in
                                    AxisValueLabel(format: .dateTime.month(.narrow)).font(Theme.smallLabel)
                                }
                            }
                            .chartYAxis {
                                AxisMarks { _ in
                                    AxisGridLine().foregroundStyle(Theme.quiet.opacity(0.5))
                                    AxisValueLabel().font(Theme.smallLabel)
                                }
                            }
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .frame(height: 240)
                            if let peak = summary.peakElectricity {
                                Label("Highest: \(peak.month.formatted(.dateTime.month(.wide))), \(peak.amount.bahtWhole) for \(peak.units.formatted()) kWh",
                                      systemImage: "thermometer.sun.fill")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                        }
                    }
                }

                Card(title: "Bill receipts", color: .orange) {
                    if billReceipts.isEmpty {
                        Text("Scan an electricity, water or internet bill and it lands here.")
                            .foregroundStyle(Theme.muted)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(Array(billReceipts)) { receipt in
                                NavigationLink {
                                    ReceiptDetailView(receipt: receipt)
                                } label: {
                                    ReceiptRow(receipt: receipt)
                                }
                                .buttonStyle(.plain)
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
        .navigationTitle("Bills")
    }
}
