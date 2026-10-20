import Foundation
import Testing
@testable import WhatToCook

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
        #expect(abs(lose.protein * 4 + lose.fat * 9 + lose.carbs * 4 - lose.kcal) < 30)
        #expect(Nutrition.norm(body: Self.body, goal: .lowcarb).carbs == 80)
        var heavy = Self.body
        heavy.weight = 80
        #expect(Nutrition.norm(body: heavy, goal: .protein).protein == 160)
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
        let row = ShoppingRow(name: "Пармезан", unit: "г", amount: 50, packSize: 150, fromFridge: 0, toBuy: 50,
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
        let context = PickContext(recipes: model.recipes, prefs: prefs)
        for day in 0..<20 {
            for kind in MealKind.allCases {
                var rng = SeededGenerator(seed: "d\(day)\(kind)")
                let dish = DishPicker.pick(meal: kind, exclude: [], context: context, using: &rng)
                #expect(dish.map { $0.carbs <= 20 && !$0.tags.contains("fish") } == true)
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

    @Test("Специи и масло не считаются купленными, пока пользователь не отметит; отметка общая для всех блюд")
    func staples() throws {
        let carbonara = try #require(model.recipes.first { $0.name == "Паста карбонара" })
        let salt = try #require(carbonara.ingredients.first { $0.isPantry })
        model.put(carbonara.id, into: .dinner)
        let row = try #require(model.rows(.dinner).first { $0.name == salt.name })
        #expect(row.isPantry && !row.have)
        #expect(model.dayShoppingRows.contains { $0.name == salt.name })

        model.toggleHave(row, in: .dinner)
        #expect(model.rows(.dinner).first { $0.name == salt.name }?.have == true)
        let lunchesWithSame = model.recipes.filter { recipe in recipe.id != carbonara.id && recipe.meal.contains(.lunch) && recipe.ingredients.contains { $0.name == salt.name } }
        let other = try #require(lunchesWithSame.first)
        model.put(other.id, into: .lunch)
        #expect(model.rows(.lunch).first { $0.name == salt.name }?.have == true)
        #expect(model.data.staples == [salt.name])
    }

    @Test("Покупки: блюда, которые уже съедены или приготовлены, в список не попадают")
    func shoppingSkipsDone() throws {
        model.ensureDay()
        let lunch = try #require(model.recipe(model.data.day?[.lunch]?.recipeID))
        let onlyLunch = Set(lunch.ingredients.map(\.name)).subtracting(MealKind.allCases.filter { $0 != .lunch }
            .flatMap { model.recipe(model.data.day?[$0]?.recipeID)?.ingredients.map(\.name) ?? [] })
        let name = try #require(onlyLunch.first)
        #expect(model.dayShoppingRows.contains { $0.name == name })
        model.toggleEaten(.lunch)
        #expect(!model.dayShoppingRows.contains { $0.name == name })
    }

    @Test("Старые сохранённые данные без новых полей открываются")
    func decodesOldState() throws {
        let old = #"{"prefs":{"cuisines":[],"avoid":[],"maxTime":40,"goal":"normal","portions":2},"onboarded":true,"diary":{},"history":[],"disliked":[],"liked":[],"fridge":[]}"#
        let data = try JSONDecoder().decode(AppData.self, from: Data(old.utf8))
        #expect(data.onboarded && data.staples.isEmpty)
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
        #expect((model.recipe(model.data.day?[.dinner]?.recipeID)?.carbs ?? 99) <= 20)
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
