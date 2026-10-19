import Foundation

extension Calendar {
    /// Gregorian calendar for all date maths, whatever calendar the phone displays.
    /// Thai phones often show the Buddhist calendar (2569), but month and year
    /// boundaries are the same, so analysis stays consistent.
    static let app: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        calendar.locale = .current
        calendar.firstWeekday = 2
        return calendar
    }()

    /// The same calendar with weeks running Sunday to Saturday, for the 7D range and its picker.
    static let sundayWeeks: Calendar = {
        var calendar = Calendar.app
        calendar.firstWeekday = 1
        return calendar
    }()
}

extension Double {
    /// ฿1,245.50, or −฿20.00 for a discount.
    var baht: String { bahtString(step: 0.01) { $0.formatted(.number.precision(.fractionLength(2))) } }
    /// ฿1,246
    var bahtWhole: String { bahtString(step: 1) { $0.formatted(.number.precision(.fractionLength(0))) } }
    /// ฿12.5K
    var bahtCompact: String { bahtString(step: 1) { $0.formatted(.number.notation(.compactName).precision(.fractionLength(0...1))) } }

    /// Puts the minus sign before ฿ rather than after it, and drops it when the amount rounds to zero.
    private func bahtString(step: Double, number: (Double) -> String) -> String {
        ((self / step).rounded() < 0 ? "−฿" : "฿") + number(abs(self))
    }
    /// 12.5%
    var percent: String { formatted(.percent.precision(.fractionLength(0...1))) }

    func roundedToSatang() -> Double { (self * 100).rounded() / 100 }
}

extension Date {
    var startOfDay: Date { Calendar.app.startOfDay(for: self) }

    var startOfMonth: Date { Calendar.app.dateInterval(of: .month, for: self)!.start }

    var year: Int { Calendar.app.component(.year, from: self) }
}
