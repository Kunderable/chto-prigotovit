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
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
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

    /// Метки для каталога — без привязки к приёму пищи.
    static func labels(_ r: Recipe) -> [String] {
        var out: [String] = []
        if r.kcal <= loseKcalMax { out.append("до 500 ккал") }
        if r.c <= lowCarbMax { out.append("мало углеводов") }
        if r.p >= proteinMin { out.append("много белка") }
        return out
    }

    static func matchesGoalFilter(_ r: Recipe, _ goal: Goal?) -> Bool {
        switch goal {
        case .lose: r.kcal <= loseKcalMax
        case .lowcarb: r.c <= lowCarbMax
        case .protein: r.p >= proteinMin
        case .normal, nil: true
        }
    }

    static func fitsGoal(_ r: Recipe, goal: Goal, meal: MealKind, target: Int?) -> Bool {
        let breakfast = meal == .breakfast
        switch goal {
        case .lowcarb: return r.c <= lowCarbMax
        case .protein: return r.p >= (breakfast ? breakfastProteinMin : proteinMin)
        case .lose:
            let limit = target.map { Double($0) * 1.15 } ?? Double(breakfast ? breakfastLoseKcalMax : loseKcalMax)
            return Double(r.kcal) <= limit
        case .normal: return true
        }
    }

    static func leftoverHits(_ r: Recipe, fridge: [FridgeItem]) -> [Ingredient] {
        r.ingredients.filter { item in !item.isPantry && fridge.contains { Shopping.same($0.name, item.n) } }
    }

    /// Вес при случайном выборе: любимое, доедаем остатки, попадает в калории приёма пищи.
    static func score(_ r: Recipe, meal: MealKind, ctx: PickContext) -> Double {
        var s = 1.0
        if ctx.liked.contains(r.id) { s += 2 }
        s += 4 * Double(leftoverHits(r, fridge: ctx.fridge).count)
        if let target = ctx.targetKcal[meal] {
            let t = Double(target)
            s += 4 * exp(-pow((Double(r.kcal) - t) / (0.3 * t), 2))
        }
        return s
    }

    /// Чем больше relax, тем больше ограничений снимается, если подходящих блюд нет.
    static func candidates(meal: MealKind, relax: Int, exclude: Set<String>, ctx: PickContext) -> [Recipe] {
        let p = ctx.prefs
        let avoid = Set(p.avoid.map(\.rawValue))
        return ctx.recipes.filter { r in
            r.meal.contains(meal)
                && !exclude.contains(r.id)
                && !ctx.disliked.contains(r.id)
                && avoid.isDisjoint(with: r.tags)
                && (relax >= 3 || !ctx.skipped.contains(r.id))
                && (relax >= 2 || fitsGoal(r, goal: p.goal, meal: meal, target: ctx.targetKcal[meal]))
                && (relax >= 1 || p.cuisines.isEmpty || p.cuisines.contains(r.cuisine))
                && (relax >= 1 || r.time <= p.maxTime)
                && (relax >= 2 || !ctx.recentIDs.contains(r.id))
        }
    }

    static func pick(meal: MealKind, exclude: Set<String>, ctx: PickContext, using rng: inout some RandomNumberGenerator) -> Recipe? {
        for relax in 0...3 {
            let list = candidates(meal: meal, relax: relax, exclude: exclude, ctx: ctx)
            guard !list.isEmpty else { continue }
            let weights = list.map { score($0, meal: meal, ctx: ctx) }
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
