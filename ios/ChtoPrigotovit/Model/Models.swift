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
    let n: String
    let a: Double?
    let u: String
    let pack: Double?
    let pantry: Bool?

    var name: String { n }
    var isPantry: Bool { pantry ?? false }
}

struct Recipe: Codable, Identifiable, Hashable {
    let id: String
    let name: String
    let emoji: String
    let cuisine: String
    let time: Int
    let base: Int
    let meal: [MealKind]
    let kcal: Int
    let p: Int
    let f: Int
    let c: Int
    let tags: [String]
    let ingredients: [Ingredient]
    let steps: [String]
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
    var p: Int
    var f: Int
    var c: Int
    var meal: MealKind?
    var recipeID: String?
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
}

struct Macros: Equatable {
    var kcal = 0, p = 0, f = 0, c = 0

    static func sum(_ items: [DiaryEntry]) -> Macros {
        items.reduce(into: Macros()) { $0.kcal += $1.kcal; $0.p += $1.p; $0.f += $1.f; $0.c += $1.c }
    }

    static func sum(_ recipes: [Recipe]) -> Macros {
        recipes.reduce(into: Macros()) { $0.kcal += $1.kcal; $0.p += $1.p; $0.f += $1.f; $0.c += $1.c }
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
