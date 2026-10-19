import Foundation

/// A monthly spending limit and where this month stands against it. Pure, so it's easy to test.
struct MoneyGoal: Equatable {
    enum State: Equatable {
        /// Spent no more than the pace for today.
        case onPace
        /// Spent more than the pace for today, still under the goal.
        case ahead
        /// Spent more than the whole goal.
        case over

        var words: String {
            switch self {
            case .onPace: "on pace"
            case .ahead: "ahead of pace"
            case .over: "over goal"
            }
        }
    }

    let goal: Double
    let spent: Double
    /// Days in the month, and which day today is (1 on the first).
    let daysInMonth: Int
    let today: Int

    init(goal: Double, spent: Double, month: DateInterval, now: Date, calendar: Calendar = .app) {
        self.goal = goal
        self.spent = spent
        daysInMonth = calendar.range(of: .day, in: .month, for: month.start)?.count ?? 30
        let day = calendar.dateComponents([.day], from: calendar.startOfDay(for: month.start), to: calendar.startOfDay(for: now)).day ?? 0
        today = min(max(day + 1, 1), daysInMonth)
    }

    /// Spent over goal; can pass 1.
    var fraction: Double { goal > 0 ? spent / goal : 0 }
    /// Where spending would be by the end of today at an even pace.
    var pace: Double { goal * Double(today) / Double(daysInMonth) }
    var paceFraction: Double { Double(today) / Double(daysInMonth) }
    var left: Double { max(goal - spent, 0) }
    var overBy: Double { max(spent - goal, 0) }
    /// Days still to spend in, today included.
    var daysLeft: Int { daysInMonth - today + 1 }
    var perDay: Double { daysLeft > 0 ? left / Double(daysLeft) : 0 }

    var state: State {
        if spent > goal { return .over }
        return spent > pace + 0.005 ? .ahead : .onPace
    }

    /// "Money goal, 62 percent used, ฿3,760 left, on pace"
    var spoken: String {
        let used = "\(Int((fraction * 100).rounded())) percent used"
        let rest = state == .over ? "over by \(overBy.bahtWhole)" : "\(left.bahtWhole) left, \(perDay.bahtWhole) a day for \(daysLeft) day\(daysLeft == 1 ? "" : "s")"
        return "Money goal, \(used), \(rest), \(state.words)"
    }

    /// A round goal near what was spent last month, for the preset key.
    static func suggestion(fromLastMonth spent: Double) -> Double? {
        guard spent > 0 else { return nil }
        return max(1_000, (spent / 1_000).rounded() * 1_000)
    }
}
