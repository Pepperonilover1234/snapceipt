import Foundation

/// Reads a receipt with plain text rules. Used when Apple Intelligence isn't available,
/// and to double-check the printed numbers (total, VAT, date) the AI returns.
enum ReceiptRules {
    static func parse(lines rawLines: [String]) -> ParsedReceipt {
        let lines = rawLines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let text = lines.joined(separator: "\n")
        let lower = text.lowercased()

        var receipt = ParsedReceipt()
        receipt.reader = .textRules
        receipt.rawText = text
        receipt.kind = kind(in: lower)
        if let date = Self.date(in: text) {
            receipt.date = date
            receipt.foundPrintedDate = true
        }
        receipt.shopName = shopName(in: lines, kind: receipt.kind)
        receipt.sellerTaxID = taxID(in: text) ?? ""
        receipt.isFullTaxInvoice = isFullTaxInvoice(lower)
        receipt.billUnits = billUnits(in: lower, kind: receipt.kind)

        var bestTotal: (priority: Int, amount: Double)?
        var pendingName: String?

        for line in lines {
            let lowered = line.lowercased()
            guard let match = trailingAmount(in: line) else {
                pendingName = line.contains(where: \.isLetter) ? line : nil
                continue
            }

            if let priority = totalPriority(lowered) {
                if bestTotal == nil || priority >= bestTotal!.priority {
                    bestTotal = (priority, match.amount)
                }
                pendingName = nil
                continue
            }
            if isVATLine(lowered) {
                receipt.vat = match.amount
                pendingName = nil
                continue
            }
            let isDiscount = lowered.contains("ส่วนลด") || lowered.contains("discount")
            if !isDiscount && shouldSkip(lowered) {
                pendingName = nil
                continue
            }

            var name = match.rest
            var count = 1.0
            if let parsed = Self.quantity(in: match.rest) {
                count = parsed.quantity
                name = parsed.name
            }
            name = cleanName(name)
            if name.count < 2 || !name.contains(where: \.isLetter) {
                name = pendingName.map(cleanName) ?? (isDiscount ? "Discount" : "Item")
            }
            let amount = isDiscount ? -abs(match.amount) : match.amount
            receipt.items.append(ParsedItem(name: name, quantity: count, total: amount))
            pendingName = nil
        }

        let itemsSum = receipt.itemsTotal
        if let bestTotal {
            receipt.total = bestTotal.amount
            receipt.foundPrintedTotal = true
        } else {
            receipt.total = itemsSum
        }

        // Restaurants and bills add VAT on top of the items: keep it as a line so items add up.
        if receipt.vat > 0,
           abs(itemsSum - receipt.total) >= 0.5,
           abs(itemsSum + receipt.vat - receipt.total) < 0.5 {
            receipt.items.append(ParsedItem(name: "VAT 7%", total: receipt.vat))
        }

        if receipt.items.isEmpty, receipt.total > 0 {
            let name = receipt.kind.isBill ? receipt.kind.name : (receipt.shopName.isEmpty ? "Purchase" : receipt.shopName)
            receipt.items = [ParsedItem(name: name, total: receipt.total)]
        }
        return receipt
    }

    // MARK: - Amounts

    /// A price at the end of a line: "นมจืด 2 x 52.00   104.00", "ส่วนลด -20.00", "1,245.00 บาท".
    static func trailingAmount(in line: String) -> (amount: Double, rest: String)? {
        guard let match = line.firstMatch(of: regex(#"(-?\d[\d,]*\.\d{2})(-?)\s*(?:บาท|baht|thb|[a-z฿*]{0,2})\s*$"#)),
              let number = match.output[1].substring,
              let value = Double(number.replacingOccurrences(of: ",", with: "")) else { return nil }
        let trailingMinus = match.output[2].substring.map { !$0.isEmpty } ?? false
        let rest = String(line[..<match.range.lowerBound]).trimmingCharacters(in: .whitespaces)
        return (trailingMinus ? -abs(value) : value, rest)
    }

    /// "2 x 52.00", "3 @ 15.00", "0.512 kg @ 89.00" before the line total.
    static func quantity(in text: String) -> (quantity: Double, name: String)? {
        guard let match = text.firstMatch(of: regex(#"^(.*?)(\d+(?:\.\d+)?)\s*(?:kg|กก\.?|ชิ้น|pcs)?\s*[x×@*]\s*\d[\d,]*(?:\.\d{1,2})?\s*$"#)),
              let qtyText = match.output[2].substring,
              let quantity = Double(qtyText), quantity > 0 else { return nil }
        let name = match.output[1].substring.map(String.init) ?? ""
        return (quantity, name)
    }

    // MARK: - Line types

    static func totalPriority(_ line: String) -> Int? {
        let finalTotals = ["ยอดสุทธิ", "รวมทั้งสิ้น", "ยอดชำระ", "ที่ต้องชำระ", "grand total", "net total", "amount due", "total due", "net amount"]
        if finalTotals.contains(where: line.contains) { return 3 }
        if line.contains("subtotal") || line.contains("sub total") || line.contains("รวมก่อน") { return 1 }
        if line.hasPrefix("รวม") || line.contains("ยอดรวม") || line.contains("รวมเงิน") || line.contains("total") { return 2 }
        return nil
    }

    static func isVATLine(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        // "VAT 7% incl. 23.55" is the VAT itself; "Amount incl. VAT 360.00" is not.
        if trimmed.hasPrefix("vat"), !trimmed.hasPrefix("vatable") { return true }
        return (line.contains("vat") || line.contains("ภาษีมูลค่าเพิ่ม"))
            && !line.contains("vatable")
            && !line.contains("incl")
            && !line.contains("ก่อน")
            && !line.contains("ไม่รวม")
    }

    static func shouldSkip(_ line: String) -> Bool {
        let skipped = [
            "cash", "เงินสด", "change", "เงินทอน", "ทอน", "credit", "card", "บัตร", "visa", "master",
            "promptpay", "พร้อมเพย์", "qr", "โอนเงิน", "transfer", "member", "สมาชิก", "point", "แต้ม", "คะแนน",
            "tax id", "เลขประจำตัว", "tel", "โทร", "เลขที่", "สาขา", "branch", "rounding", "ปัดเศษ",
            "vatable", "ก่อนภาษี", "มูลค่าสินค้า", "received", "รับเงิน", "ชำระโดย", "paid by",
        ]
        return skipped.contains(where: line.contains)
    }

    static func cleanName(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: #"^\d{5,}\s*"#, with: "", options: .regularExpression)
        name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
        return name.trimmingCharacters(in: CharacterSet(charactersIn: " -:.*#/"))
    }

    // MARK: - Header facts

    static func kind(in text: String) -> ReceiptKind {
        if text.contains("การไฟฟ้า") || text.contains("ค่าไฟฟ้า") || text.contains("kwh")
            || hasWord("mea", in: text) || hasWord("pea", in: text) || text.contains("electricity") {
            return .electricity
        }
        if text.contains("การประปา") || text.contains("ค่าน้ำประปา") || text.contains("ลบ.ม")
            || hasWord("mwa", in: text) || hasWord("pwa", in: text) || text.contains("water supply") || text.contains("waterworks") {
            return .water
        }
        if text.contains("อินเทอร์เน็ต") || text.contains("internet") || text.contains("fibre") || text.contains("fiber")
            || text.contains("broadband") || text.contains("postpaid") || text.contains("รายเดือนโทรศัพท์") {
            return .internet
        }
        return .purchase
    }

    /// Thailand's utility providers, named the way they print on bills.
    private static let billProviders: [(names: [String], display: String)] = [
        (["การไฟฟ้านครหลวง", "metropolitan electricity"], "การไฟฟ้านครหลวง (MEA)"),
        (["การไฟฟ้าส่วนภูมิภาค", "provincial electricity"], "การไฟฟ้าส่วนภูมิภาค (PEA)"),
        (["การประปานครหลวง", "metropolitan waterworks"], "การประปานครหลวง (MWA)"),
        (["การประปาส่วนภูมิภาค", "provincial waterworks"], "การประปาส่วนภูมิภาค (PWA)"),
    ]

    static func shopName(in lines: [String], kind: ReceiptKind) -> String {
        if kind.isBill {
            let lower = lines.joined(separator: " ").lowercased()
            if let provider = billProviders.first(where: { $0.names.contains(where: lower.contains) }) {
                return provider.display
            }
        }
        let notNames = ["ใบเสร็จ", "receipt", "tax invoice", "ใบกำกับ", "สาขา", "branch", "tax id", "เลขประจำตัว",
                        "tel", "โทร", "วันที่", "date", "pos", "ใบแจ้ง", "bill", "welcome", "ยินดีต้อนรับ",
                        "หน่วย", "kwh", "โต๊ะ", "table"]
        for line in lines.prefix(6) {
            let lowered = line.lowercased()
            guard line.contains(where: \.isLetter),
                  line.count >= 3,
                  trailingAmount(in: line) == nil,
                  !notNames.contains(where: lowered.contains) else { continue }
            return cleanName(line)
        }
        return kind.isBill ? kind.name : ""
    }

    static func taxID(in text: String) -> String? {
        guard let match = text.firstMatch(of: regex(#"(?:tax\s*id|เลขประจำตัวผู้เสียภาษี|เลขผู้เสียภาษี|เลขที่ผู้เสียภาษี)[^\d]{0,12}([\d\- ]{13,20})"#)),
              let raw = match.output[1].substring else { return nil }
        let digits = raw.filter(\.isNumber)
        return digits.count == 13 ? String(digits) : nil
    }

    static func isFullTaxInvoice(_ text: String) -> Bool {
        if text.contains("อย่างย่อ") || hasWord("abb", in: text) { return false }
        if text.contains("เต็มรูป") || text.contains("full tax invoice") || text.contains("e-tax invoice") { return true }
        return text.contains("tax invoice")
            && (text.contains("ชื่อผู้ซื้อ") || text.contains("ชื่อลูกค้า") || text.contains("customer name") || text.contains("buyer"))
    }

    /// Units used on a bill: "หน่วยที่ใช้ 486 หน่วย", "486 kWh", "ใช้น้ำ 18 ลบ.ม.".
    /// Read one line at a time, so a number at the end of the line above (a date) can't be taken.
    static func billUnits(in text: String, kind: ReceiptKind) -> Double {
        let unit: String
        switch kind {
        case .electricity: unit = #"(?:หน่วย|kwh)"#
        case .water: unit = #"(?:ลบ\.?\s?ม|m3|m³|cubic)"#
        default: return 0
        }
        let number = #"(\d[\d,]*(?:\.\d+)?)"#
        let usedWords = ["ใช้", "used", "consum"]
        let lines = text.components(separatedBy: .newlines)
            .filter { !$0.contains("บาท/") && !$0.contains("baht/") && !$0.contains("/หน่วย") }
        // Lines that say "used" first, then any line with a unit.
        let ordered = lines.filter { line in usedWords.contains(where: line.contains) }
            + lines.filter { line in !usedWords.contains(where: line.contains) }
        for line in ordered {
            let match = line.firstMatch(of: regex(number + #"[ \t]*"# + unit))
                ?? line.firstMatch(of: regex(unit + #"[^\d\n]{0,16}"# + number))
            if let match, let raw = match.output[1].substring,
               let value = Double(raw.replacingOccurrences(of: ",", with: "")), value > 0 {
                return value
            }
        }
        return 0
    }

    // MARK: - Dates

    private static let thaiMonths: [[String]] = [
        ["ม.ค.", "มกราคม"], ["ก.พ.", "กุมภาพันธ์"], ["มี.ค.", "มีนาคม"], ["เม.ย.", "เมษายน"],
        ["พ.ค.", "พฤษภาคม"], ["มิ.ย.", "มิถุนายน"], ["ก.ค.", "กรกฎาคม"], ["ส.ค.", "สิงหาคม"],
        ["ก.ย.", "กันยายน"], ["ต.ค.", "ตุลาคม"], ["พ.ย.", "พฤศจิกายน"], ["ธ.ค.", "ธันวาคม"],
    ]
    private static let englishMonths = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

    /// Thai receipts write dates as day/month/year, often in Buddhist years (2569, or just 69).
    static func date(in text: String) -> Date? {
        var day: Int?
        var month: Int?
        var year: Int?

        if let match = text.firstMatch(of: regex(#"(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})"#)) {
            day = match.output[1].substring.flatMap { Int($0) }
            month = match.output[2].substring.flatMap { Int($0) }
            year = match.output[3].substring.flatMap { Int($0) }
            if let d = day, let m = month, m > 12, d <= 12 { day = m; month = d }
        } else {
            for (index, names) in thaiMonths.enumerated() {
                let alternatives = names.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
                if let match = text.firstMatch(of: regex(#"(\d{1,2})\s*(?:"# + alternatives + #")\s*(\d{2,4})"#)) {
                    day = match.output[1].substring.flatMap { Int($0) }
                    month = index + 1
                    year = match.output[2].substring.flatMap { Int($0) }
                    break
                }
            }
            if day == nil {
                let lowered = text.lowercased()
                for (index, name) in englishMonths.enumerated() {
                    if let match = lowered.firstMatch(of: regex(#"(\d{1,2})\s*"# + name + #"[a-z]*\.?,?\s*(\d{2,4})"#)) {
                        day = match.output[1].substring.flatMap { Int($0) }
                        month = index + 1
                        year = match.output[2].substring.flatMap { Int($0) }
                        break
                    }
                }
            }
        }

        guard let day, let month, let year, (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents(year: gregorianYear(year), month: month, day: day, hour: 12)
        if let time = text.firstMatch(of: regex(#"(\d{1,2}):(\d{2})"#)),
           let hour = time.output[1].substring.flatMap({ Int($0) }),
           let minute = time.output[2].substring.flatMap({ Int($0) }),
           (0...23).contains(hour), (0...59).contains(minute) {
            components.hour = hour
            components.minute = minute
        }
        guard let date = Calendar.app.date(from: components) else { return nil }
        // A misread date far in the past or future is worse than today's date.
        let now = Date.now
        guard date < now.addingTimeInterval(86_400 * 2), date > now.addingTimeInterval(-86_400 * 365 * 5) else { return nil }
        return date
    }

    /// 2569 → 2026, 69 → 2026, 26 → 2026.
    static func gregorianYear(_ year: Int) -> Int {
        switch year {
        case 2400...: year - 543
        case 100...: year
        case 60...99: 2500 + year - 543
        default: 2000 + year
        }
    }

    // MARK: - Helpers

    private static func regex(_ pattern: String) -> Regex<AnyRegexOutput> {
        (try! Regex(pattern)).ignoresCase()
    }

    private static func hasWord(_ word: String, in text: String) -> Bool {
        text.firstMatch(of: regex(#"\b"# + word + #"\b"#)) != nil
    }
}
