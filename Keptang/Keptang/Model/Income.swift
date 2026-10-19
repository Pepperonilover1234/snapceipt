import SwiftUI

/// Where money coming in came from.
enum IncomeSource: String, CaseIterable, Identifiable, Codable {
    case salary, freelance, sales, gift, refund, investment, other

    var id: String { rawValue }

    var name: String {
        switch self {
        case .salary: "Salary"
        case .freelance: "Freelance & side work"
        case .sales: "Sold something"
        case .gift: "Gift & allowance"
        case .refund: "Refund"
        case .investment: "Interest & dividends"
        case .other: "Other income"
        }
    }

    var thaiName: String {
        switch self {
        case .salary: "เงินเดือน"
        case .freelance: "งานเสริม"
        case .sales: "ขายของ"
        case .gift: "ของขวัญ/เงินให้"
        case .refund: "เงินคืน"
        case .investment: "ดอกเบี้ย/ปันผล"
        case .other: "รายได้อื่น"
        }
    }

    var symbol: String {
        switch self {
        case .salary: "briefcase.fill"
        case .freelance: "laptopcomputer"
        case .sales: "tag.fill"
        case .gift: "gift.fill"
        case .refund: "arrow.uturn.backward.circle.fill"
        case .investment: "chart.line.uptrend.xyaxis"
        case .other: "plus.circle.fill"
        }
    }

    /// Thai and English words that mean money came in from this source. Checked in order.
    static let keywords: [(IncomeSource, [String])] = [
        (.salary, ["เงินเดือน", "salary", "payroll", "paycheck", "pay day", "payday", "wage", "ค่าแรง", "โบนัส", "bonus"]),
        (.freelance, ["ฟรีแลนซ์", "freelance", "งานเสริม", "ค่าจ้าง", "side job", "commission", "ค่าคอม", "client", "ลูกค้าจ่าย", "invoice paid"]),
        (.sales, ["ขาย", "sold", "sale of", "selling", "ขายของ", "ขายได้"]),
        (.refund, ["คืนเงิน", "เงินคืน", "refund", "cashback", "cash back", "reimburse", "เบิกคืน", "เบิกได้"]),
        (.investment, ["ดอกเบี้ย", "ปันผล", "interest", "dividend", "หุ้น", "stock profit", "กำไร"]),
        (.gift, ["แม่ให้", "พ่อให้", "ให้มา", "อั่งเปา", "angpao", "ang pao", "ค่าขนม", "pocket money", "allowance", "gift from", "birthday money", "ได้เงิน"]),
        (.other, ["รายได้", "income", "got paid", "received", "ได้รับ", "earned", "earn", "เงินเข้า", "money in", "โอนเข้า", "transfer in"]),
    ]
}
