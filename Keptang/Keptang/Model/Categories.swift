import SwiftUI

/// What an item was spent on.
///
/// Raw values are stored in the database, so they never change. `home` is a legacy category:
/// items saved with it keep it, but new scans and the pickers no longer offer it.
enum SpendCategory: String, CaseIterable, Identifiable, Codable {
    case groceries, dining, transport, shopping, health, home, utilities, entertainment, other
    case subscriptions, education

    var id: String { rawValue }

    /// The categories people can choose, in the order they're shown.
    static let selectable: [SpendCategory] = [
        .dining, .groceries, .utilities, .transport, .shopping, .health, .entertainment, .subscriptions, .education, .other,
    ]

    /// The category new guesses use instead of a legacy one.
    var current: SpendCategory { self == .home ? .shopping : self }

    var name: String {
        switch self {
        case .groceries: "Groceries"
        case .dining: "Food & Drinks"
        case .transport: "Transportation"
        case .shopping: "Shopping"
        case .health: "Health"
        case .home: "Home"
        case .utilities: "Utilities"
        case .entertainment: "Entertainment"
        case .subscriptions: "Subscriptions"
        case .education: "Education"
        case .other: "Other"
        }
    }

    var thaiName: String {
        switch self {
        case .groceries: "ของกินของใช้"
        case .dining: "อาหารและเครื่องดื่ม"
        case .transport: "เดินทาง"
        case .shopping: "ช้อปปิ้ง"
        case .health: "สุขภาพและความงาม"
        case .home: "ของใช้ในบ้าน"
        case .utilities: "ค่าน้ำค่าไฟ"
        case .entertainment: "บันเทิง"
        case .subscriptions: "สมาชิกรายเดือน"
        case .education: "การศึกษา"
        case .other: "อื่น ๆ"
        }
    }

    var symbol: String {
        switch self {
        case .groceries: "cart.fill"
        case .dining: "fork.knife"
        case .transport: "tram.fill"
        case .shopping: "bag.fill"
        case .health: "cross.case.fill"
        case .home: "sofa.fill"
        case .utilities: "bolt.fill"
        case .entertainment: "popcorn.fill"
        case .subscriptions: "arrow.triangle.2.circlepath"
        case .education: "graduationcap.fill"
        case .other: "square.grid.2x2.fill"
        }
    }

    /// Fill behind the category's icon and its share bar. Always under navy, never text.
    var color: Color {
        switch self {
        case .groceries: Theme.lime
        case .dining: Theme.orange
        case .transport: Theme.sky
        case .shopping: Theme.pink
        case .health: Theme.mint
        case .home: Theme.purple
        case .utilities: Theme.yellow
        case .entertainment: Theme.coral
        case .subscriptions: Theme.cyan
        case .education: Theme.peach
        case .other: Theme.stone
        }
    }
}

/// What kind of document a receipt is. Bills are tracked separately per year.
enum ReceiptKind: String, CaseIterable, Identifiable, Codable {
    case purchase, electricity, water, internet

    var id: String { rawValue }

    var isBill: Bool { self != .purchase }

    var name: String {
        switch self {
        case .purchase: "Purchase"
        case .electricity: "Electricity"
        case .water: "Water"
        case .internet: "Internet & phone"
        }
    }

    var symbol: String {
        switch self {
        case .purchase: "cart.fill"
        case .electricity: "bolt.fill"
        case .water: "drop.fill"
        case .internet: "wifi"
        }
    }

    static let billKinds: [ReceiptKind] = [.electricity, .water, .internet]

    /// Bottom-to-top order in stacked bill charts.
    var stackOrder: Int { Self.billKinds.firstIndex(of: self) ?? 0 }

    /// Chart colour. Each passes 3:1 against the background in light and dark,
    /// and blue against orange stays apart for colour-blind readers.
    var color: Color {
        switch self {
        case .purchase, .electricity: Theme.ink
        case .water: Theme.chartBlue
        case .internet: Theme.chartOrange
        }
    }

    /// Fill behind the bill's icon.
    var fill: Color {
        switch self {
        case .purchase: Theme.stone
        case .electricity: Theme.yellow
        case .water: Theme.sky
        case .internet: Theme.orange
        }
    }

    /// Unit printed on the bill, if it has one.
    var unit: String? {
        switch self {
        case .electricity: "kWh"
        case .water: "m³"
        default: nil
        }
    }
}

extension SpendCategory {
    /// The card colour that matches this category's fill.
    var cardColor: CardColor {
        switch self {
        case .groceries: .lime
        case .dining: .orange
        case .transport: .sky
        case .shopping: .pink
        case .health: .mint
        case .home: .purple
        case .utilities: .yellow
        case .entertainment: .coral
        case .subscriptions: .cyan
        case .education: .peach
        case .other: .peach
        }
    }
}

extension ReceiptKind {
    var cardColor: CardColor {
        switch self {
        case .purchase: .peach
        case .electricity: .yellow
        case .water: .sky
        case .internet: .orange
        }
    }
}
