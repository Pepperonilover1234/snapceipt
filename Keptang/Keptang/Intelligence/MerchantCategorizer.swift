import Foundation

/// Sorts a receipt's items using who sold them as well as what they are.
///
/// Per item, in order:
/// 1. The person's correction for the same item name.
/// 2. The category the person chose for this merchant's whole receipt before.
/// 3. For shops that only sell one kind of thing (restaurants, transport, subscriptions,
///    education, entertainment, health, utilities), the shop's category.
/// 4. The item's own guess: Create ML, Apple Intelligence, then keywords.
/// 5. At supermarkets and convenience stores, Groceries where that guess found nothing better.
enum MerchantCategorizer {
    enum MerchantType: String, CaseIterable {
        case supermarket, restaurant, transport, subscription, education, entertainment, health, utility

        var category: SpendCategory {
            switch self {
            case .supermarket: .groceries
            case .restaurant: .dining
            case .transport: .transport
            case .subscription: .subscriptions
            case .education: .education
            case .entertainment: .entertainment
            case .health: .health
            case .utility: .utilities
            }
        }

        /// True when everything bought there belongs to the shop's category.
        /// Supermarkets sell all sorts, so their items keep their own guesses.
        var isStrong: Bool { self != .supermarket }
    }

    /// Checked in this order, so "GrabFood" is a restaurant before "Grab" is transport
    /// and "Café Amazon" is a cafe. Latin keywords match whole words; Thai ones match anywhere,
    /// because Thai is written without spaces.
    static let merchants: [(MerchantType, [String])] = [
        (.utility, ["การไฟฟ้า", "การประปา", "mea", "pea", "mwa", "pwa", "metropolitan electricity", "provincial electricity",
                    "waterworks authority"]),
        (.subscription, ["netflix", "spotify", "youtube", "icloud", "apple.com", "itunes", "apple music", "apple one", "apple tv",
                         "disney", "hbo", "viu", "trueid", "true id", "google one", "google storage", "prime video"]),
        (.restaurant, ["grabfood", "grab food", "line man", "lineman", "foodpanda", "restaurant", "restaurants", "ร้านอาหาร", "cafe", "คาเฟ่",
                       "coffee", "กาแฟ", "starbucks", "amazon", "kfc", "mcdonald", "mcdonald's", "mk", "mk restaurants", "bar b q",
                       "barbq", "sizzler", "pizza", "ก๋วยเตี๋ยว", "ข้าว", "ชาบู", "หมูกระทะ", "food court", "foodcourt", "ฟู้ดคอร์ท",
                       "kitchen", "ครัว", "bakery", "เบเกอรี่", "burger", "sushi", "ramen", "bistro", "dessert"]),
        (.supermarket, ["lotus's", "lotus", "lotuss", "tesco", "big c", "bigc", "tops", "makro", "villa market", "gourmet market",
                        "foodland", "maxvalu", "7-eleven", "7 eleven", "7eleven", "seven eleven", "familymart", "family mart",
                        "lawson", "cj", "cj more", "cj express", "supermarket", "mini mart", "minimart", "ท็อปส์", "บิ๊กซี",
                        "โลตัส", "แม็คโคร", "เซเว่น", "ซูเปอร์มาร์เก็ต"]),
        (.transport, ["bts", "mrt", "grab", "bolt", "taxi", "แท็กซี่", "ptt", "shell", "bangchak", "caltex", "esso", "ปตท", "บางจาก",
                      "airasia", "air asia", "airways", "airlines", "nok air", "thai lion", "vietjet", "การบินไทย", "รถไฟ",
                      "expressway", "ทางด่วน", "easy pass", "parking", "ที่จอดรถ"]),
        (.education, ["school", "โรงเรียน", "university", "มหาวิทยาลัย", "college", "วิทยาลัย", "tuition", "กวดวิชา", "course",
                      "academy", "chula", "จุฬา", "se-ed", "ซีเอ็ด", "b2s", "kinokuniya", "asia books"]),
        (.entertainment, ["major cineplex", "sf cinema", "sfx", "cinema", "cineplex", "โรงภาพยนตร์", "karaoke", "คาราโอเกะ",
                          "concert", "ticket", "bowling", "โบว์ลิ่ง"]),
        (.health, ["boots", "watsons", "pharmacy", "ร้านยา", "เภสัช", "hospital", "โรงพยาบาล", "clinic", "คลินิก", "dental",
                   "ทันตกรรม"]),
    ]

    /// What kind of shop this is, if the name says.
    static func merchantType(for shopName: String) -> MerchantType? {
        let name = normalize(shopName)
        guard !name.isEmpty else { return nil }
        let words = latinWords(in: name)
        for (type, keywords) in merchants where keywords.contains(where: { matches($0, name: name, words: words) }) {
            return type
        }
        return nil
    }

    /// The category for one item on a receipt from `shopName`.
    static func category(
        forItem itemName: String,
        shopName: String,
        aiGuess: SpendCategory?,
        learner: CategoryLearner = .shared
    ) -> SpendCategory {
        if let learned = learner.learnedCategory(forItem: itemName) { return learned }
        if let merchant = learner.learnedCategory(forMerchant: shopName) { return merchant }
        let type = merchantType(for: shopName)
        if let type, type.isStrong { return type.category }
        let guess = learner.guess(for: itemName, aiGuess: aiGuess)
        if type == .supermarket, guess == .other { return .groceries }
        return guess
    }

    /// Lower case, single spaces, accents folded on Latin letters only.
    /// Thai vowel and tone marks change the word, so they are kept.
    static func normalize(_ name: String) -> String {
        let folded = name.unicodeScalars.map { scalar -> String in
            let character = String(scalar)
            let isThai = (0x0E00...0x0E7F).contains(scalar.value)
            return isThai ? character : character.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en"))
        }.joined()
        return folded
            .replacingOccurrences(of: "’", with: "'")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func latinWords(in name: String) -> String {
        // Spaces around the name so whole-word checks also work at the ends.
        " " + name.replacingOccurrences(of: #"[^a-z0-9'.+&-]+"#, with: " ", options: .regularExpression) + " "
    }

    private static func matches(_ keyword: String, name: String, words: String) -> Bool {
        let isLatin = keyword.unicodeScalars.allSatisfy { $0.value < 0x0E00 }
        return isLatin ? words.contains(" \(keyword) ") : name.contains(keyword)
    }
}
