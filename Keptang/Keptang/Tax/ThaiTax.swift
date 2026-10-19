import Foundation

/// Thai VAT and personal income tax rules used for the tax planning screen.
enum ThaiTax {
    /// VAT is 7% and Thai shelf prices include it.
    static let vatRate = 0.07

    /// VAT inside a VAT-inclusive price: total × 7 / 107.
    static func vatIncluded(in total: Double) -> Double {
        (total * vatRate / (1 + vatRate)).roundedToSatang()
    }

    static func priceBeforeVAT(_ total: Double) -> Double {
        (total - vatIncluded(in: total)).roundedToSatang()
    }

    struct Bracket {
        let upTo: Double
        let rate: Double
    }

    /// Progressive personal income tax on net (taxable) income.
    static let brackets: [Bracket] = [
        Bracket(upTo: 150_000, rate: 0),
        Bracket(upTo: 300_000, rate: 0.05),
        Bracket(upTo: 500_000, rate: 0.10),
        Bracket(upTo: 750_000, rate: 0.15),
        Bracket(upTo: 1_000_000, rate: 0.20),
        Bracket(upTo: 2_000_000, rate: 0.25),
        Bracket(upTo: 5_000_000, rate: 0.30),
        Bracket(upTo: .infinity, rate: 0.35),
    ]

    static func incomeTax(on taxable: Double) -> Double {
        var tax = 0.0
        var lower = 0.0
        for bracket in brackets {
            if taxable > lower {
                tax += (min(taxable, bracket.upTo) - lower) * bracket.rate
            }
            lower = bracket.upTo
        }
        return tax.roundedToSatang()
    }

    static func marginalRate(on taxable: Double) -> Double {
        brackets.first { taxable <= $0.upTo }?.rate ?? 0.35
    }

    /// Personal allowance (ค่าลดหย่อนส่วนตัว).
    static let personalAllowance = 60_000.0

    /// Salary expense deduction: 50% of employment income, at most ฿100,000.
    static func employmentExpenseDeduction(annualSalary: Double) -> Double {
        min(annualSalary * 0.5, 100_000)
    }

    /// Social security contribution is 5% of wages, capped at a wage of ฿17,500 a month from 2026 (฿875 a month).
    static func socialSecurity(monthlySalary: Double) -> Double {
        min(monthlySalary, 17_500) * 0.05 * 12
    }

    static func estimate(monthlySalary: Double, otherDeductions: Double, shoppingDeduction: Double) -> TaxEstimate {
        let annual = max(0, monthlySalary) * 12
        return TaxEstimate(
            annualIncome: annual,
            expenseDeduction: employmentExpenseDeduction(annualSalary: annual),
            personalAllowance: personalAllowance,
            socialSecurity: socialSecurity(monthlySalary: max(0, monthlySalary)),
            otherDeductions: max(0, otherDeductions),
            shoppingDeduction: max(0, shoppingDeduction)
        )
    }
}

struct TaxEstimate {
    var annualIncome: Double
    var expenseDeduction: Double
    var personalAllowance: Double
    var socialSecurity: Double
    var otherDeductions: Double
    var shoppingDeduction: Double

    var taxableBefore: Double {
        max(0, annualIncome - expenseDeduction - personalAllowance - socialSecurity - otherDeductions)
    }
    var taxableAfter: Double { max(0, taxableBefore - shoppingDeduction) }
    var taxBefore: Double { ThaiTax.incomeTax(on: taxableBefore) }
    var taxAfter: Double { ThaiTax.incomeTax(on: taxableAfter) }
    var saved: Double { taxBefore - taxAfter }
    var marginalRate: Double { ThaiTax.marginalRate(on: taxableBefore) }
}
