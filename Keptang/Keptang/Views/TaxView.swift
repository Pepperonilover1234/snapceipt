import SwiftData
import SwiftUI

struct TaxView: View {
    @Query(filter: #Predicate<Receipt> { $0.isIncome == false }, sort: \Receipt.date) private var receipts: [Receipt]
    @AppStorage("monthlySalary") private var monthlySalary = 45_000.0
    @AppStorage("otherDeductions") private var otherDeductions = 0.0
    @AppStorage("shoppingCap") private var shoppingCap = 50_000.0
    @AppStorage("shoppingStart") private var shoppingStart = TaxView.defaultStart
    @AppStorage("shoppingEnd") private var shoppingEnd = TaxView.defaultEnd

    static var defaultStart: Double {
        Calendar.app.date(from: DateComponents(year: Date.now.year, month: 1, day: 1))!.timeIntervalSince1970
    }
    static var defaultEnd: Double {
        Calendar.app.date(from: DateComponents(year: Date.now.year, month: 12, day: 31))!.timeIntervalSince1970
    }

    private struct MissedInvoice: Identifiable {
        let shop: String
        let count: Int
        let total: Double
        var id: String { shop }
    }

    var body: some View {
        let year = Date.now.year
        let thisYear = receipts.filter { $0.date.year == year }
        let vatPaid = thisYear.reduce(0) { $0 + $1.vat }
        let start = Date(timeIntervalSince1970: shoppingStart).startOfDay
        let end = Calendar.app.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: shoppingEnd).startOfDay)!
        let eligible = thisYear.filter { $0.isFullTaxInvoice && !$0.kind.isBill && $0.date >= start && $0.date < end }
        let eligibleSpend = eligible.reduce(0) { $0 + $1.total }
        let deduction = min(eligibleSpend, max(0, shoppingCap))
        let estimate = ThaiTax.estimate(monthlySalary: monthlySalary, otherDeductions: otherDeductions, shoppingDeduction: deduction)
        let missed = missedInvoices(in: thisYear)

        CardPage {
            CardSection(title: "Your income", note: "Other deductions are per year: life and health insurance, SSF/RMF, home loan interest, parents and children. Only used on this phone.", color: .lime) {
                LabeledContent("Monthly salary") {
                    BahtField(title: "Monthly salary", value: $monthlySalary, fractionDigits: 0)
                }
                LabeledContent("Other deductions") {
                    BahtField(title: "Other deductions per year", value: $otherDeductions, fractionDigits: 0)
                }
            }

            CardSection(title: "VAT you paid in \(String(year))", color: .sky) {
                AmountRow("VAT 7% inside your receipts", vatPaid.baht)
                AmountRow("Receipts this year", "\(thisYear.count)")
                AmountRow("Full tax invoices", "\(thisYear.filter(\.isFullTaxInvoice).count)")
            }

            CardSection(title: "Shopping tax deduction", note: "Schemes like Easy E-Receipt let you deduct spending on full tax invoices or e-Tax invoices. Easy E-Receipt 2.0 ran 16 Jan – 28 Feb 2025, up to ฿50,000 (฿30,000 at any VAT shop plus ฿20,000 at OTOP and community shops). Set this year's dates and limit when the Revenue Department announces them.", color: .pink) {
                DateField(title: "From", date: dateBinding($shoppingStart), components: .date)
                DateField(title: "To", date: dateBinding($shoppingEnd), components: .date)
                LabeledContent("Deduction limit") {
                    BahtField(title: "Deduction limit", value: $shoppingCap, fractionDigits: 0)
                }
                AmountRow("Full tax invoices in these dates", eligibleSpend.baht)
                VStack(alignment: .leading, spacing: 6) {
                    MeterBar(fraction: shoppingCap > 0 ? deduction / shoppingCap : 0)
                    Text("\(deduction.bahtWhole) of \(shoppingCap.bahtWhole) used")
                        .font(.footnote).foregroundStyle(Theme.muted)
                }
                .padding(.vertical, 6)
                .accessibilityElement(children: .combine)
            }

            CardSection(title: "Estimated income tax", note: "Your top tax rate is \(estimate.marginalRate.percent), so each ฿1,000 on a full tax invoice saves about \((estimate.marginalRate * 1_000).bahtWhole) while the limit lasts. This is an estimate; file with the Revenue Department (rd.go.th).", color: .purple) {
                AmountRow("Income this year", estimate.annualIncome.bahtWhole)
                AmountRow("Salary expense deduction (50%, max ฿100,000)", "−" + estimate.expenseDeduction.bahtWhole)
                AmountRow("Personal allowance", "−" + estimate.personalAllowance.bahtWhole)
                AmountRow("Social security", "−" + estimate.socialSecurity.bahtWhole)
                if estimate.otherDeductions > 0 {
                    AmountRow("Other deductions", "−" + estimate.otherDeductions.bahtWhole)
                }
                AmountRow("Taxable income", estimate.taxableBefore.bahtWhole)
                AmountRow("Tax without shopping deduction", estimate.taxBefore.bahtWhole)
                AmountRow("Tax with shopping deduction", estimate.taxAfter.bahtWhole)
                AmountRow("You save", estimate.saved.bahtWhole, emphasized: true)
            }

            if !missed.isEmpty {
                CardSection(title: "Ask for a full tax invoice here", note: "You've had full tax invoices from these shops before, so they can issue one. Ask at the till with your name and ID number.", color: .orange) {
                    ForEach(missed) { shop in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(shop.shop).font(.body.weight(.semibold)).foregroundStyle(Theme.ink)
                                Text("\(shop.count) receipts without a full tax invoice").font(.footnote).foregroundStyle(Theme.muted)
                            }
                            Spacer()
                            Text(shop.total.bahtWhole).font(Theme.figure()).foregroundStyle(Theme.ink)
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
    }

    private func dateBinding(_ storage: Binding<Double>) -> Binding<Date> {
        Binding(
            get: { Date(timeIntervalSince1970: storage.wrappedValue) },
            set: { storage.wrappedValue = $0.timeIntervalSince1970 }
        )
    }

    private func missedInvoices(in receipts: [Receipt]) -> [MissedInvoice] {
        let shopsThatIssue = Set(receipts.filter(\.isFullTaxInvoice).map(\.shopName))
        let missed = receipts.filter { !$0.isFullTaxInvoice && !$0.kind.isBill && shopsThatIssue.contains($0.shopName) }
        return Dictionary(grouping: missed, by: \.shopName)
            .map { MissedInvoice(shop: $0.key, count: $0.value.count, total: $0.value.reduce(0) { $0 + $1.total }) }
            .sorted { $0.total > $1.total }
            .prefix(4)
            .map { $0 }
    }
}
