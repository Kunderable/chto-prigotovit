import Foundation

/// Детерминированный генератор: одинаковое зерно (например, дата) даёт одинаковый план дня.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    init(seed: String) {
        var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        state = hash
    }

    mutating func next() -> UInt64 { // SplitMix64
        state &+= 0x9e3779b97f4a7c15
        var mixed = state
        mixed = (mixed ^ (mixed >> 30)) &* 0xbf58476d1ce4e5b9
        mixed = (mixed ^ (mixed >> 27)) &* 0x94d049bb133111eb
        return mixed ^ (mixed >> 31)
    }
}

/// Всё, что влияет на выбор блюда.
struct PickContext {
    var recipes: [Recipe]
    var prefs: Prefs
    var disliked: Set<String> = []
    var liked: Set<String> = []
    var fridge: [FridgeItem] = []
    var recentIDs: Set<String> = []
    var skipped: Set<String> = []
    var targetKcal: [MealKind: Int] = [:]
}

enum DishPicker {
    static let lowCarbMax = 20
    static let loseKcalMax = 500
    static let proteinMin = 35
    static let breakfastLoseKcalMax = 400
    static let breakfastProteinMin = 20
    /// При похудении блюдо может быть на столько больше калорий приёма пищи.
    static let loseKcalTolerance = 1.15

    // Вес при случайном выборе
    static let likedBonus = 2.0
    static let leftoverBonus = 4.0
    static let kcalFitBonus = 4.0
    /// Насколько широко «попадание в калории»: доля от цели приёма пищи.
    static let kcalFitWidth = 0.3

    /// Метки для каталога — без привязки к приёму пищи.
    static func labels(_ recipe: Recipe) -> [String] {
        var labels: [String] = []
        if recipe.kcal <= loseKcalMax { labels.append("до \(loseKcalMax) ккал") }
        if recipe.carbs <= lowCarbMax { labels.append("мало углеводов") }
        if recipe.protein >= proteinMin { labels.append("много белка") }
        return labels
    }

    static func matchesGoalFilter(_ recipe: Recipe, _ goal: Goal?) -> Bool {
        switch goal {
        case .lose: recipe.kcal <= loseKcalMax
        case .lowcarb: recipe.carbs <= lowCarbMax
        case .protein: recipe.protein >= proteinMin
        case .normal, nil: true
        }
    }

    static func fitsGoal(_ recipe: Recipe, goal: Goal, meal: MealKind, target: Int?) -> Bool {
        let breakfast = meal == .breakfast
        switch goal {
        case .lowcarb: return recipe.carbs <= lowCarbMax
        case .protein: return recipe.protein >= (breakfast ? breakfastProteinMin : proteinMin)
        case .lose:
            let limit = target.map { Double($0) * loseKcalTolerance } ?? Double(breakfast ? breakfastLoseKcalMax : loseKcalMax)
            return Double(recipe.kcal) <= limit
        case .normal: return true
        }
    }

    static func leftoverHits(_ recipe: Recipe, fridge: [FridgeItem]) -> [Ingredient] {
        recipe.ingredients.filter { item in !item.isPantry && fridge.contains { Shopping.same($0.name, item.name) } }
    }

    /// Вес при случайном выборе: любимое, доедаем остатки, попадает в калории приёма пищи.
    static func score(_ recipe: Recipe, meal: MealKind, context: PickContext) -> Double {
        var weight = 1.0
        if context.liked.contains(recipe.id) { weight += likedBonus }
        weight += leftoverBonus * Double(leftoverHits(recipe, fridge: context.fridge).count)
        if let target = context.targetKcal[meal].map(Double.init) {
            // колокол Гаусса: чем ближе калории блюда к цели, тем ближе бонус к максимуму
            weight += kcalFitBonus * exp(-pow((Double(recipe.kcal) - target) / (kcalFitWidth * target), 2))
        }
        return weight
    }

    /// Чем больше relax, тем больше ограничений снимается, если подходящих блюд нет.
    static func candidates(meal: MealKind, relax: Int, exclude: Set<String>, context: PickContext) -> [Recipe] {
        let prefs = context.prefs
        let avoid = Set(prefs.avoid.map(\.rawValue))
        return context.recipes.filter { recipe in
            recipe.meal.contains(meal)
                && !exclude.contains(recipe.id)
                && !context.disliked.contains(recipe.id)
                && avoid.isDisjoint(with: recipe.tags)
                && (relax >= 3 || !context.skipped.contains(recipe.id))
                && (relax >= 2 || fitsGoal(recipe, goal: prefs.goal, meal: meal, target: context.targetKcal[meal]))
                && (relax >= 1 || prefs.cuisines.isEmpty || prefs.cuisines.contains(recipe.cuisine))
                && (relax >= 1 || recipe.time <= prefs.maxTime)
                && (relax >= 2 || !context.recentIDs.contains(recipe.id))
        }
    }

    static func pick(meal: MealKind, exclude: Set<String>, context: PickContext, using rng: inout some RandomNumberGenerator) -> Recipe? {
        for relax in 0...3 {
            let list = candidates(meal: meal, relax: relax, exclude: exclude, context: context)
            guard !list.isEmpty else { continue }
            let weights = list.map { score($0, meal: meal, context: context) }
            var roll = Double.random(in: 0..<weights.reduce(0, +), using: &rng)
            for (recipe, weight) in zip(list, weights) {
                roll -= weight
                if roll <= 0 { return recipe }
            }
            return list.last
        }
        return nil
    }
}
