import SwiftUI

/// Printable Thai receipts for trying the scanner in the simulator, where there's no camera.
/// They're rendered to an image and go through the same Vision + AI pipeline as a real photo.
enum SampleReceipt: String, CaseIterable, Identifiable {
    case supermarket, restaurant, electricity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .supermarket: "Supermarket, full tax invoice"
        case .restaurant: "Restaurant with service charge"
        case .electricity: "Electricity bill"
        }
    }

    var symbol: String {
        switch self {
        case .supermarket: "cart"
        case .restaurant: "fork.knife"
        case .electricity: "bolt"
        }
    }

    /// Today's date as Thai receipts print it: day/month/Buddhist year (17/10/69).
    private var printedDate: String {
        let calendar = Calendar.app
        let now = Date.now
        let day = calendar.component(.day, from: now)
        let month = calendar.component(.month, from: now)
        let buddhistYear = (calendar.component(.year, from: now) + 543) % 100
        return String(format: "%02d/%02d/%02d", day, month, buddhistYear)
    }

    var lines: [PaperLine] {
        switch self {
        case .supermarket:
            [
                .title("ตลาดดี ซูเปอร์มาร์เก็ต"),
                .center("TALADDEE SUPERMARKET CO., LTD."),
                .center("สาขา อารีย์  โทร 02-000-0000"),
                .center("TAX ID 0105560000017"),
                .center("ใบกำกับภาษีเต็มรูป / TAX INVOICE"),
                .center("ชื่อผู้ซื้อ: สมชาย ใจดี"),
                .row("วันที่ \(printedDate)", "เวลา 13:42"),
                .rule,
                .row("นมจืด เมจิ 2 ลิตร", "95.00"),
                .row("ไข่ไก่ เบอร์ 2 แพ็ค 10", "59.00"),
                .row("ขนมปังโฮลวีท ฟาร์มเฮ้าส์", ""),
                .row("   2 x 32.00", "64.00"),
                .row("อกไก่ ซีพี 1 กก.", "129.00"),
                .row("ข้าวหอมมะลิ 5 กก.", "235.00"),
                .row("น้ำยาล้างจาน ซันไลต์", "45.00"),
                .row("กระดาษทิชชู่ 6 ม้วน", "119.00"),
                .row("ยาสีฟัน คอลเกต", "89.00"),
                .row("ส้มสายน้ำผึ้ง 1 กก.", "79.00"),
                .row("ส่วนลดสมาชิก", "-20.00"),
                .rule,
                .row("รวม 10 รายการ", "894.00"),
                .bold("ยอดสุทธิ / TOTAL", "894.00"),
                .row("มูลค่าก่อนภาษี / VATABLE", "835.51"),
                .row("ภาษีมูลค่าเพิ่ม VAT 7%", "58.49"),
                .row("เงินสด / CASH", "1,000.00"),
                .row("เงินทอน / CHANGE", "106.00"),
                .gap,
                .center("ขอบคุณที่ใช้บริการ"),
            ]
        case .restaurant:
            [
                .title("ร้านอาหาร ครัวบ้านสวน"),
                .center("BAAN SUAN KITCHEN"),
                .center("TAX ID 0105561000025"),
                .center("ใบเสร็จรับเงิน / ใบกำกับภาษีอย่างย่อ"),
                .row("โต๊ะ 12  วันที่ \(printedDate)", "เวลา 19:25"),
                .rule,
                .row("ต้มยำกุ้งน้ำข้น", "220.00"),
                .row("ผัดกะเพราหมูกรอบ", "120.00"),
                .row("ปลากะพงทอดน้ำปลา", "380.00"),
                .row("ข้าวสวย", ""),
                .row("   3 @ 15.00", "45.00"),
                .row("ชาไทยเย็น", ""),
                .row("   2 @ 55.00", "110.00"),
                .rule,
                .row("รวมค่าอาหาร", "875.00"),
                .row("Service Charge 10%", "87.50"),
                .row("VAT 7%", "67.38"),
                .bold("ยอดสุทธิ / GRAND TOTAL", "1,029.88"),
                .row("ชำระโดย บัตรเครดิต VISA", "1,029.88"),
                .gap,
                .center("Thank you / ขอบคุณค่ะ"),
            ]
        case .electricity:
            [
                .title("ใบแจ้งค่าไฟฟ้า"),
                .center("ELECTRICITY BILL (SAMPLE)"),
                .row("วันที่อ่าน \(printedDate)", ""),
                .row("หน่วยที่ใช้ 486 หน่วย (kWh)", ""),
                .rule,
                .row("ค่าพลังงานไฟฟ้า", "2,034.39"),
                .row("ค่าบริการรายเดือน", "38.22"),
                .row("ค่า Ft (0.3972 บาท/หน่วย)", "193.04"),
                .row("รวมเงินค่าไฟฟ้า", "2,265.65"),
                .row("ภาษีมูลค่าเพิ่ม 7%", "158.60"),
                .bold("รวมเงินที่ต้องชำระ", "2,424.25"),
            ]
        }
    }

    @MainActor
    func image() -> UIImage {
        let renderer = ImageRenderer(content: ReceiptPaper(lines: lines))
        renderer.scale = 3
        return renderer.uiImage ?? UIImage()
    }
}

enum PaperLine {
    case title(String)
    case center(String)
    case row(String, String)
    case bold(String, String)
    case rule
    case gap
}

struct ReceiptPaper: View {
    let lines: [PaperLine]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                switch line {
                case .title(let text):
                    Text(text).font(.system(size: 20, weight: .bold)).frame(maxWidth: .infinity)
                case .center(let text):
                    Text(text).font(.system(size: 14)).frame(maxWidth: .infinity)
                case .row(let left, let right):
                    HStack {
                        Text(left)
                        Spacer(minLength: 24)
                        Text(right).monospacedDigit()
                    }
                    .font(.system(size: 15))
                case .bold(let left, let right):
                    HStack {
                        Text(left)
                        Spacer(minLength: 24)
                        Text(right).monospacedDigit()
                    }
                    .font(.system(size: 16, weight: .bold))
                case .rule:
                    Rectangle().frame(height: 1).padding(.vertical, 4)
                case .gap:
                    Color.clear.frame(height: 10)
                }
            }
        }
        .foregroundStyle(.black)
        .padding(28)
        .frame(width: 420)
        .background(Color.white)
        .environment(\.colorScheme, .light)
    }
}
