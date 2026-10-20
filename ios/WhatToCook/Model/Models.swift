import Foundation

// Данные рецептов приходят из data/recipes/*.json через build.mjs.

enum MealKind: String, Codable, CaseIterable, Identifiable {
    case breakfast, lunch, dinner
    var id: String { rawValue }

    var title: String {
        switch self {
        case .breakfast: "Завтрак"
        case .lunch: "Обед"
        case .dinner: "Ужин"
        }
    }

    /// Доля дневной нормы калорий.
    var share: Double {
        switch self {
        case .breakfast: 0.25
        case .lunch: 0.4
        case .dinner: 0.35
        }
    }
}

struct Ingredient: Codable, Hashable {
    let name: String
    /// nil — «по вкусу».
    let amount: Double?
    let unit: String
    /// Сколько в одной магазинной упаковке, если продукт продаётся упаковками.
    let packSize: Double?
    /// Соль, специи, масло — то, что обычно покупают впрок.
    let isPantry: Bool

    // В JSON рецептов поля короткие, чтобы файл с 500+ рецептами весил меньше.
    private enum CodingKeys: String, CodingKey {
        case name = "n", amount = "a", unit = "u", packSize = "pack", isPantry = "pantry"
    }

    init(name: String, amount: Double?, unit: String, packSize: Double?, isPantry: Bool) {
        self.name = name
        self.amount = amount
        self.unit = unit
        self.packSize = packSize
        self.isPantry = isPantry
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        amount = try container.decodeIfPresent(Double.self, forKey: .amount)
        unit = try container.decode(String.self, forKey: .unit)
        packSize = try container.decodeIfPresent(Double.self, forKey: .packSize)
        isPantry = try container.decodeIfPresent(Bool.self, forKey: .isPantry) ?? false
    }
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let cuisine: String
    let time: Int
    /// На сколько порций записаны количества продуктов.
    let servings: Int
    let meal: [MealKind]
    /// Калории и БЖУ на одну порцию.
    let kcal: Int
    let protein: Int
    let fat: Int
    let carbs: Int
    let tags: [String]
    let ingredients: [Ingredient]
    let steps: [String]

    private enum CodingKeys: String, CodingKey {
        case id, name, emoji, cuisine, time, servings = "base", meal, kcal
        case protein = "p", fat = "f", carbs = "c", tags, ingredients, steps
    }
}

struct Price: Codable {
    let rub: Double
    let unit: String
    let gramsPerPiece: Double
}

enum Goal: String, Codable, CaseIterable, Identifiable {
    case normal, lose, protein, lowcarb
    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal: "Просто вкусно"
        case .lose: "Похудеть"
        case .protein: "Больше белка"
        case .lowcarb: "Мало углеводов"
        }
    }
}

enum Sex: String, Codable, CaseIterable, Identifiable {
    case female = "f", male = "m"
    var id: String { rawValue }
    var title: String { self == .female ? "Женщина" : "Мужчина" }
}

enum Restriction: String, Codable, CaseIterable, Identifiable {
    case meat, pork, fish, dairy, gluten
    var id: String { rawValue }

    var title: String {
        switch self {
        case .meat: "Мясо и птица"
        case .pork: "Свинина"
        case .fish: "Рыба и морепродукты"
        case .dairy: "Молочное"
        case .gluten: "Глютен"
        }
    }
}

struct Prefs: Codable, Equatable {
    var cuisines: [String] = ["русская", "итальянская", "грузинская", "японская"]
    var avoid: [Restriction] = []
    var maxTime: Int = 40
    var goal: Goal = .normal
    var portions: Int = 2
}

struct BodyData: Codable, Equatable {
    var sex: Sex
    var age: Int
    var height: Double
    var weight: Double
    var activity: Double
}

struct PlannedMeal: Codable, Equatable {
    var recipeID: String
    var portions: Int
    var have: Set<String> = []
    var cooked = false
    var rated = false
    var eaten = false
}

struct DayPlan: Codable, Equatable {
    var date: String
    var meals: [String: PlannedMeal] = [:]

    subscript(kind: MealKind) -> PlannedMeal? {
        get { meals[kind.rawValue] }
        set { meals[kind.rawValue] = newValue }
    }
}

struct DiaryEntry: Codable, Identifiable, Equatable {
    var id: String
    var name: String
    var kcal: Int
    var protein: Int
    var fat: Int
    var carbs: Int
    var meal: MealKind?
    var recipeID: String?

    // Ключи совпадают с прошлыми версиями, чтобы сохранённый дневник читался.
    private enum CodingKeys: String, CodingKey {
        case id, name, kcal, protein = "p", fat = "f", carbs = "c", meal, recipeID
    }
}

struct FridgeItem: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var amount: Double?
    var unit: String
}

struct HistoryItem: Codable, Equatable {
    var recipeID: String
    var name: String
    var date: String
}

/// Всё, что сохраняется на устройстве.
struct AppData: Codable, Equatable {
    var prefs = Prefs()
    var body: BodyData?
    var onboarded = false
    var day: DayPlan?
    var diary: [String: [DiaryEntry]] = [:]
    var history: [HistoryItem] = []
    var disliked: [String] = []
    var liked: [String] = []
    var fridge: [FridgeItem] = []
    /// Специи, масло и прочее, что по словам пользователя всегда есть дома.
    var staples: [String] = []
}

extension AppData {
    private enum CodingKeys: String, CodingKey {
        case prefs, body, onboarded, day, diary, history, disliked, liked, fridge, staples
    }

    /// Поля, которых не было в прошлых версиях, берутся по умолчанию — иначе сохранённые данные потерялись бы.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppData()
        prefs = try container.decodeIfPresent(Prefs.self, forKey: .prefs) ?? defaults.prefs
        body = try container.decodeIfPresent(BodyData.self, forKey: .body)
        onboarded = try container.decodeIfPresent(Bool.self, forKey: .onboarded) ?? defaults.onboarded
        day = try container.decodeIfPresent(DayPlan.self, forKey: .day)
        diary = try container.decodeIfPresent([String: [DiaryEntry]].self, forKey: .diary) ?? defaults.diary
        history = try container.decodeIfPresent([HistoryItem].self, forKey: .history) ?? defaults.history
        disliked = try container.decodeIfPresent([String].self, forKey: .disliked) ?? defaults.disliked
        liked = try container.decodeIfPresent([String].self, forKey: .liked) ?? defaults.liked
        fridge = try container.decodeIfPresent([FridgeItem].self, forKey: .fridge) ?? defaults.fridge
        staples = try container.decodeIfPresent([String].self, forKey: .staples) ?? defaults.staples
    }
}

struct Macros: Equatable {
    var kcal = 0, protein = 0, fat = 0, carbs = 0

    static func sum(_ entries: [DiaryEntry]) -> Macros {
        entries.reduce(into: Macros()) { total, entry in
            total.kcal += entry.kcal
            total.protein += entry.protein
            total.fat += entry.fat
            total.carbs += entry.carbs
        }
    }
}

enum Catalog {
    static let cuisines: [(id: String, hue: Double)] = [
        ("русская", 205), ("итальянская", 12), ("грузинская", 330), ("узбекская", 45),
        ("французская", 230), ("средиземноморская", 185), ("американская", 0), ("мексиканская", 35),
        ("ближневосточная", 25), ("индийская", 50), ("китайская", 355), ("японская", 340),
        ("корейская", 15), ("тайская", 95), ("испанская", 20), ("вьетнамская", 160),
    ]
    static let times: [(value: Int, title: String)] = [(20, "до 20 мин"), (40, "до 40 мин"), (999, "не важно")]
    static let units = ["г", "мл", "шт", "зубч.", "ст.л.", "ч.л."]
    static let maxPortions = 8

    static func hue(for cuisine: String) -> Double {
        cuisines.first { $0.id == cuisine }?.hue ?? 140
    }
}
