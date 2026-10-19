import Foundation
import NaturalLanguage

/// Decides each item's category and learns from the person's corrections.
///
/// Order of trust (see `MerchantCategorizer` for how the merchant fits in):
/// 1. A correction the person made for the same item name.
/// 2. A category the person chose for the whole receipt at the same merchant.
/// 3. The merchant's own category, for shops that only sell one kind of thing.
/// 4. The Create ML text classifier (ItemCategory.mlmodel) when it's confident,
///    then Apple Intelligence's guess, then Thai and English keyword rules.
final class CategoryLearner {
    static let shared = CategoryLearner()

    private let defaultsKey = "learnedCategories"
    private static let merchantPrefix = "merchant:"
    private let defaults: UserDefaults
    /// Item names and, under "merchant:" keys, merchant names, mapped to category raw values.
    private var learned: [String: String]
    private let model: NLModel?

    init(defaults: UserDefaults = .standard, loadModel: Bool = true) {
        self.defaults = defaults
        learned = defaults.dictionary(forKey: defaultsKey) as? [String: String] ?? [:]
        if loadModel, let url = Bundle.main.url(forResource: "ItemCategory", withExtension: "mlmodelc") {
            model = try? NLModel(contentsOf: url)
        } else {
            model = nil
        }
    }

    var hasCreateMLModel: Bool { model != nil }
    /// Item names the person has re-sorted.
    var learnedCount: Int { learned.keys.filter { !$0.hasPrefix(Self.merchantPrefix) }.count }

    /// The learned category for this item name, or else the best automatic guess.
    func category(for name: String, aiGuess: SpendCategory?) -> SpendCategory {
        learnedCategory(forItem: name) ?? guess(for: name, aiGuess: aiGuess)
    }

    func learnedCategory(forItem name: String) -> SpendCategory? {
        learned[Self.normalize(name)].flatMap(SpendCategory.init(rawValue:))
    }

    func learnedCategory(forMerchant name: String) -> SpendCategory? {
        let key = MerchantCategorizer.normalize(name)
        guard !key.isEmpty else { return nil }
        return learned[Self.merchantPrefix + key].flatMap(SpendCategory.init(rawValue:))
    }

    /// Create ML, then Apple Intelligence, then keywords. Never returns a legacy category.
    func guess(for name: String, aiGuess: SpendCategory?) -> SpendCategory {
        let key = Self.normalize(name)
        let modelGuess = self.modelGuess(key)
        if let modelGuess, modelGuess.confidence >= 0.75 { return modelGuess.category.current }
        if let aiGuess, aiGuess != .other { return aiGuess.current }
        if let keyword = Self.keywordGuess(key) { return keyword.current }
        return modelGuess?.category.current ?? .other
    }

    func learn(_ name: String, as category: SpendCategory) {
        let key = Self.normalize(name)
        guard !key.isEmpty else { return }
        learned[key] = category.rawValue
        defaults.set(learned, forKey: defaultsKey)
    }

    /// Remembers that everything bought at this merchant belongs to one category.
    func learnMerchant(_ name: String, as category: SpendCategory) {
        let key = MerchantCategorizer.normalize(name)
        guard !key.isEmpty else { return }
        learned[Self.merchantPrefix + key] = category.rawValue
        defaults.set(learned, forKey: defaultsKey)
    }

    func forgetAll() {
        learned = [:]
        defaults.removeObject(forKey: defaultsKey)
    }

    private func modelGuess(_ text: String) -> (category: SpendCategory, confidence: Double)? {
        guard let model, !text.isEmpty,
              let best = model.predictedLabelHypotheses(for: text, maximumCount: 1).first,
              let category = SpendCategory(rawValue: best.key) else { return nil }
        return (category, best.value)
    }

    static func normalize(_ name: String) -> String {
        name.lowercased()
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Checked in order: dishes (ข้าวมันไก่, ชานม) before raw groceries (ไก่, นม), and cooking oil before fuel.
    static let keywords: [(SpendCategory, [String])] = [
        (.utilities, ["ค่าไฟ", "ค่าพลังงานไฟฟ้า", "ค่า ft", "ค่าน้ำประปา", "อินเทอร์เน็ต", "internet", "fibre", "electricity", "water bill", "ค่าส่วนกลาง", "postpaid"]),
        (.dining, ["กาแฟ", "ลาเต้", "อเมริกาโน่", "ชาไทย", "ชาเย็น", "ชานม", "กะเพรา", "ผัดไทย", "ส้มตำ", "ต้มยำ", "ข้าวมันไก่", "ก๋วยเตี๋ยว",
                   "สุกี้", "ชาบู", "หมูกระทะ", "ติ่มซำ", "เป็ดย่าง", "บิงซู", "เค้ก", "ค่าบริการ", "service charge",
                   "coffee", "latte", "americano", "cappuccino", "milk tea", "green tea latte", "burger", "pizza", "fried rice", "pad thai", "set menu", "ramen", "sushi", "cake"]),
        (.groceries, ["นม", "ไข่", "ข้าวหอม", "ข้าวสาร", "ขนมปัง", "ผัก", "หมู", "ไก่", "เนื้อ", "ปลา", "กุ้ง", "ผลไม้", "ส้ม", "กล้วย", "แอปเปิ้ล",
                      "น้ำปลา", "ซีอิ๊ว", "น้ำมันพืช", "น้ำตาล", "เกลือ", "มาม่า", "บะหมี่", "น้ำดื่ม", "โยเกิร์ต", "เต้าหู้",
                      "milk", "egg", "rice", "bread", "chicken", "pork", "beef", "fish", "fruit", "banana", "apple", "yogurt", "cheese",
                      "butter", "noodle", "cereal", "vegetable", "drinking water"]),
        (.transport, ["bts", "mrt", "grab", "bolt", "taxi", "แท็กซี่", "วิน", "แก๊สโซฮอล์", "เบนซิน", "ดีเซล", "gasohol", "diesel", "e20",
                      "ทางด่วน", "toll", "easy pass", "ที่จอดรถ", "parking", "rabbit", "แรบบิท", "ค่าโดยสาร", "fare", "ตั๋วรถ", "flight"]),
        (.health, ["ยาแก้", "ยาพารา", "ยาดม", "ยาหม่อง", "วิตามิน", "พลาสเตอร์", "หน้ากาก", "กันแดด", "แชมพู", "สบู่", "ยาสีฟัน", "แปรงสีฟัน", "โฟมล้างหน้า", "โลชั่น", "คลินิก", "ทันตกรรม",
                   "paracetamol", "vitamin", "sunscreen", "shampoo", "soap", "toothpaste", "lotion", "clinic", "dental", "gym", "fitness"]),
        (.shopping, ["น้ำยาล้างจาน", "ผงซักฟอก", "ปรับผ้านุ่ม", "ทิชชู่", "กระดาษชำระ", "ถุงขยะ", "น้ำยาถูพื้น", "หลอดไฟ", "ปลั๊ก", "หมอน", "ผ้าปู", "ผ้าเช็ดตัว",
                 "กระทะ", "หม้อ", "พัดลม", "ถ่าน", "detergent", "tissue", "toilet paper", "garbage bag", "bulb", "pillow", "towel", "frying pan", "electric fan", "battery"]),
        (.subscriptions, ["netflix", "spotify", "youtube premium", "youtube", "disney+", "disney plus", "icloud", "apple music", "apple one",
                          "google one", "hbo", "viu", "trueid", "prime video", "subscription", "membership", "ค่าสมาชิก", "รายเดือน"]),
        (.education, ["ค่าเทอม", "ค่าเรียน", "กวดวิชา", "หนังสือเรียน", "แบบเรียน", "คอร์ส", "ติวเตอร์", "tuition", "course", "textbook", "workbook",
                      "tutor", "workshop", "exam fee", "ค่าสอบ"]),
        (.entertainment, ["ตั๋วหนัง", "ภาพยนตร์", "ป๊อปคอร์น", "คอนเสิร์ต", "คาราโอเกะ", "โบว์ลิ่ง", "movie",
                          "cinema", "popcorn", "concert", "karaoke", "game", "steam", "playstation", "nintendo"]),
        (.shopping, ["เสื้อ", "กางเกง", "รองเท้า", "กระเป๋า", "หูฟัง", "สายชาร์จ", "เคส", "แบตสำรอง", "นาฬิกา", "แว่น", "ของเล่น", "หนังสือ", "ปากกา", "สมุด",
                     "shirt", "t-shirt", "jeans", "shoes", "sneakers", "bag", "headphone", "earbuds", "cable", "case", "power bank", "watch",
                     "book", "toy", "ipad", "iphone", "laptop", "keyboard"]),
    ]

    static func keywordGuess(_ name: String) -> SpendCategory? {
        for (category, words) in keywords where words.contains(where: name.contains) {
            return category
        }
        return nil
    }
}
