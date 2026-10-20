import Foundation
import Testing
@testable import ChtoPrigotovit

/// Логика без интерфейса на настоящих рецептах и ценах из приложения.
struct LogicTests {
    let model: AppModel
    static let body = BodyData(sex: .female, age: 30, height: 165, weight: 65, activity: 1.375)

    init() {
        let live = AppModel.live()
        model = AppModel(recipes: live.recipes, prices: live.pricing.prices)
    }

    @Test("Рецепты и цены загружаются из ресурсов")
    func resourcesLoad() {
        #expect(model.recipes.count > 500)
        #expect(model.recipes.contains { $0.meal.contains(.breakfast) })
    }

    @Test("Норма: дефицит при похудении, БЖУ сходятся с калориями")
    func norm() {
        let lose = Nutrition.norm(body: Self.body, goal: .lose)
        let normal = Nutrition.norm(body: Self.body, goal: .normal)
        #expect(lose.kcal < normal.kcal)
        #expect(abs(lose.p * 4 + lose.f * 9 + lose.c * 4 - lose.kcal) < 30)
        #expect(Nutrition.norm(body: Self.body, goal: .lowcarb).c == 80)
        var heavy = Self.body
        heavy.weight = 80
        #expect(Nutrition.norm(body: heavy, goal: .protein).p == 160)
    }

    @Test("Ввод данных: пустые поля и границы")
    func bodyInput() throws {
        #expect(throws: Nutrition.BodyInputError.missing("возраст")) {
            try Nutrition.parseBody(sex: .female, age: "", height: "165", weight: "65", activity: 1.375)
        }
        #expect(throws: Nutrition.BodyInputError.self) {
            try Nutrition.parseBody(sex: .female, age: "30", height: "300", weight: "65", activity: 1.375)
        }
        let body = try Nutrition.parseBody(sex: .male, age: "30", height: "180", weight: "80,5", activity: 1.2)
        #expect(body.weight == 80.5)
    }

    @Test("Цены есть у каждого рецепта, упаковки покупаются целиком")
    func prices() {
        #expect(model.recipes.allSatisfy { model.portionCost($0) != nil })
        #expect(model.pricing.unitPrice("Картофель", unit: "шт") == 9)
        let row = ShoppingRow(name: "Пармезан", unit: "г", amount: 50, pack: 150, fromFridge: 0, toBuy: 50,
                              have: false, packs: 1, leftover: 100, inFridge: false)
        #expect(model.pricing.buyCost([row]) == 450)
    }

    @Test("План дня: три разных блюда нужного типа")
    func dayPlan() throws {
        model.data.body = Self.body
        model.ensureDay()
        let day = try #require(model.data.day)
        let ids = MealKind.allCases.compactMap { day[$0]?.recipeID }
        #expect(Set(ids).count == 3)
        for kind in MealKind.allCases {
            #expect(model.recipe(day[kind]?.recipeID)?.meal.contains(kind) == true)
        }
    }

    @Test("Подбор соблюдает «мало углеводов» и «не ем»")
    func picking() {
        var prefs = Prefs()
        prefs.goal = .lowcarb
        prefs.cuisines = []
        prefs.avoid = [.fish]
        let ctx = PickContext(recipes: model.recipes, prefs: prefs)
        for day in 0..<20 {
            for kind in MealKind.allCases {
                var rng = SeededGenerator(seed: "d\(day)\(kind)")
                let r = DishPicker.pick(meal: kind, exclude: [], ctx: ctx, using: &rng)
                #expect(r.map { $0.c <= 20 && !$0.tags.contains("fish") } == true)
            }
        }
    }

    @Test("«Съел»: запись появляется и исчезает; замена блюда её не стирает")
    func eaten() throws {
        model.ensureDay()
        model.toggleEaten(.lunch)
        #expect(model.diaryToday.count == 1)
        model.toggleEaten(.lunch)
        #expect(model.diaryToday.isEmpty)
        model.toggleEaten(.lunch)
        let current = try #require(model.data.day?[.lunch]?.recipeID)
        let other = try #require(model.recipes.first { $0.meal.contains(.lunch) && $0.id != current })
        model.put(other.id, into: .lunch)
        #expect(model.diaryToday.count == 1)
        #expect(model.data.day?[.lunch]?.eaten == false)
    }

    @Test("«Приготовил»: остаток упаковки уходит в холодильник")
    func cooking() throws {
        let carbonara = try #require(model.recipes.first { $0.name == "Паста карбонара" })
        model.put(carbonara.id, into: .dinner)
        model.cook(.dinner)
        let parmesan = try #require(model.data.fridge.first { $0.name == "Пармезан" })
        #expect(parmesan.amount == 100)
    }

    @Test("Смена цели: съеденное остаётся, остальное подбирается заново")
    func replan() throws {
        model.data.body = Self.body
        model.ensureDay()
        let breakfast = try #require(model.data.day?[.breakfast]?.recipeID)
        model.toggleEaten(.breakfast)
        var prefs = model.data.prefs
        prefs.goal = .lowcarb
        model.updatePrefs(prefs)
        #expect(model.data.day?[.breakfast]?.recipeID == breakfast)
        #expect(model.data.day?[.breakfast]?.eaten == true)
        #expect((model.recipe(model.data.day?[.dinner]?.recipeID)?.c ?? 99) <= 20)
    }

    @Test("Время суток выбирает приём пищи")
    func clock() {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: .now)
        #expect(AppModel.mealByClock(calendar.date(byAdding: .hour, value: 9, to: day)!) == .breakfast)
        #expect(AppModel.mealByClock(calendar.date(byAdding: .hour, value: 13, to: day)!) == .lunch)
        #expect(AppModel.mealByClock(calendar.date(byAdding: .hour, value: 20, to: day)!) == .dinner)
    }
}
