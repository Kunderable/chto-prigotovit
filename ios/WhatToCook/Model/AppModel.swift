import Foundation
import Observation
import os

@Observable
final class AppModel {
    let recipes: [Recipe]
    let pricing: Pricing
    private let index: [String: Recipe]
    private let storeURL: URL?
    private static let log = Logger(subsystem: "ru.chtoprigotovit.app", category: "store")

    var data: AppData { didSet { if data != oldValue { save() } } }
    /// Пролистанные кнопкой «Другое» — чтобы не предлагать их снова в тот же день.
    var skipped: [MealKind: Set<String>] = [:]

    init(recipes: [Recipe], prices: [String: Price], data: AppData = AppData(), storeURL: URL? = nil) {
        self.recipes = recipes
        self.pricing = Pricing(prices: prices)
        self.index = Dictionary(uniqueKeysWithValues: recipes.map { ($0.id, $0) })
        self.storeURL = storeURL
        self.data = data
    }

    static func live() -> AppModel {
        let decoder = JSONDecoder()
        let recipes = (try? decoder.decode([Recipe].self, from: resource("recipes"))) ?? []
        let prices = (try? decoder.decode([String: Price].self, from: resource("prices"))) ?? [:]
        let url = URL.applicationSupportDirectory.appending(path: "state.json")
        let saved = (try? Data(contentsOf: url)).flatMap { try? decoder.decode(AppData.self, from: $0) }
        return AppModel(recipes: recipes, prices: prices, data: saved ?? AppData(), storeURL: url)
    }

    private static func resource(_ name: String) -> Data {
        guard let url = Bundle.main.url(forResource: name, withExtension: "json"), let data = try? Data(contentsOf: url) else {
            log.error("Нет ресурса \(name, privacy: .public).json")
            return Data()
        }
        return data
    }

    private func save() {
        guard let storeURL else { return }
        do {
            try FileManager.default.createDirectory(at: storeURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(data).write(to: storeURL, options: .atomic)
        } catch {
            Self.log.error("Не удалось сохранить: \(error.localizedDescription, privacy: .public)")
        }
    }

    func recipe(_ id: String?) -> Recipe? { id.flatMap { index[$0] } }
    var norm: DailyNorm? { data.body.map { Nutrition.norm(body: $0, goal: data.prefs.goal) } }
    func target(_ meal: MealKind) -> Int? { norm.map { Int((Double($0.kcal) * meal.share).rounded()) } }
    func portionCost(_ recipe: Recipe) -> Int? { pricing.portionCost(recipe) }

    static func dayKey(_ date: Date = .now) -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }

    // MARK: - План на день

    static func mealByClock(_ date: Date = .now) -> MealKind {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 11 { return .breakfast }
        return hour < 16 ? .lunch : .dinner
    }

    func focusMeal(_ date: Date = .now) -> (meal: MealKind, isNext: Bool) {
        let now = Self.mealByClock(date)
        let order = MealKind.allCases
        let next = order[order.firstIndex(of: now)!...].first { kind in
            guard let planned = data.day?[kind] else { return false }
            return !planned.eaten
        }
        return (next ?? now, next != nil && next != now)
    }

    private func pickContext() -> PickContext {
        var targets: [MealKind: Int] = [:]
        for kind in MealKind.allCases { targets[kind] = target(kind) }
        return PickContext(recipes: recipes, prefs: data.prefs, disliked: Set(data.disliked), liked: Set(data.liked),
                           fridge: data.fridge, recentIDs: Set(data.history.suffix(6).map(\.recipeID)), targetKcal: targets)
    }

    private func otherIDs(_ day: DayPlan, except kind: MealKind) -> Set<String> {
        Set(MealKind.allCases.filter { $0 != kind }.compactMap { day[$0]?.recipeID })
    }

    func ensureDay(now: Date = .now) {
        let date = Self.dayKey(now)
        var day = data.day?.date == date ? data.day! : DayPlan(date: date)
        var changed = data.day != day
        var context = pickContext()
        for kind in MealKind.allCases {
            if let planned = day[kind], recipe(planned.recipeID) != nil, planned.cooked || !data.disliked.contains(planned.recipeID) { continue }
            context.skipped = skipped[kind] ?? []
            var rng = SeededGenerator(seed: date + kind.rawValue)
            let dish = DishPicker.pick(meal: kind, exclude: otherIDs(day, except: kind), context: context, using: &rng)
            day[kind] = dish.map { PlannedMeal(recipeID: $0.id, portions: data.prefs.portions) }
            changed = true
        }
        if changed { data.day = day }
    }

    func put(_ recipeID: String, into kind: MealKind) {
        ensureDay()
        guard var day = data.day else { return }
        // запись в дневнике не трогаем: съеденное остаётся съеденным, даже если блюдо в плане заменили
        day[kind] = PlannedMeal(recipeID: recipeID, portions: data.prefs.portions)
        data.day = day
    }

    @discardableResult
    func reroll(_ kind: MealKind) -> Bool {
        guard let day = data.day, let current = day[kind]?.recipeID else { return false }
        skipped[kind, default: []].insert(current)
        var context = pickContext()
        context.skipped = skipped[kind] ?? []
        var rng = SystemRandomNumberGenerator()
        guard let dish = DishPicker.pick(meal: kind, exclude: otherIDs(day, except: kind).union([current]), context: context, using: &rng) else { return false }
        put(dish.id, into: kind)
        return true
    }

    func neverAgain(_ kind: MealKind) {
        guard let id = data.day?[kind]?.recipeID else { return }
        data.disliked.append(id)
        reroll(kind)
    }

    func update(_ kind: MealKind, _ change: (inout PlannedMeal) -> Void) {
        guard var day = data.day, var meal = day[kind] else { return }
        change(&meal)
        day[kind] = meal
        data.day = day
    }

    func replanKeepingDone() {
        guard var day = data.day, day.date == Self.dayKey() else { return }
        day.meals = day.meals.filter { $0.value.eaten || $0.value.cooked }
        data.day = day
        ensureDay()
    }

    func updatePrefs(_ prefs: Prefs) {
        let goalChanged = prefs.goal != data.prefs.goal
        data.prefs = prefs
        if goalChanged { replanKeepingDone() }
    }

    func setBody(_ body: BodyData?) {
        data.body = body
        replanKeepingDone()
    }

    // MARK: - Покупки, готовка, «съел»

    func rows(_ kind: MealKind) -> [ShoppingRow] {
        guard let planned = data.day?[kind], let dish = recipe(planned.recipeID) else { return [] }
        return Shopping.rows(dish, plan: planned, fridge: data.fridge, staples: data.staples)
    }

    var shoppingGroups: [(kind: MealKind, recipe: Recipe, rows: [ShoppingRow])] {
        MealKind.allCases.compactMap { kind in
            guard let planned = data.day?[kind], planned.inShopping, !planned.cooked, !planned.eaten,
                  let dish = recipe(planned.recipeID) else { return nil }
            return (kind, dish, rows(kind))
        }
    }

    var dayShoppingRows: [ShoppingRow] { Shopping.merge(shoppingGroups.map(\.rows)) }

    func toggleShopping(_ kind: MealKind) {
        update(kind) { $0.inShopping.toggle() }
    }

    /// У специй отметка общая для всех блюд, у остальных продуктов — только для этого блюда.
    func toggleHave(_ row: ShoppingRow, in kind: MealKind) {
        if row.isPantry {
            let has = data.staples.contains { Shopping.same($0, row.name) }
            data.staples = has ? data.staples.filter { !Shopping.same($0, row.name) } : data.staples + [row.name]
        } else {
            update(kind) { meal in
                if meal.have.contains(row.name) { meal.have.remove(row.name) } else { meal.have.insert(row.name) }
            }
        }
    }

    func removeStaple(_ name: String) { data.staples = data.staples.filter { !Shopping.same($0, name) } }

    @discardableResult
    func cook(_ kind: MealKind) -> [String] {
        guard let planned = data.day?[kind], let dish = recipe(planned.recipeID) else { return [] }
        let after = Shopping.fridgeAfterCooking(dish, plan: planned, fridge: data.fridge)
        data.fridge = after.fridge
        data.history = Array((data.history + [HistoryItem(recipeID: dish.id, name: dish.name, date: Self.dayKey())]).suffix(60))
        update(kind) { $0.cooked = true }
        return after.added
    }

    func rate(_ kind: MealKind, good: Bool) {
        guard let id = data.day?[kind]?.recipeID else { return }
        if good {
            if !data.liked.contains(id) { data.liked.append(id) }
        } else {
            data.liked.removeAll { $0 == id }
            if !data.disliked.contains(id) { data.disliked.append(id) }
        }
        update(kind) { $0.rated = true }
    }

    var diaryToday: [DiaryEntry] { data.diary[Self.dayKey()] ?? [] }
    var eatenToday: Macros { Macros.sum(diaryToday) }

    private func setDiaryToday(_ entries: [DiaryEntry]) {
        data.diary[Self.dayKey()] = entries
        let keep = Set(data.diary.keys.sorted().suffix(30))
        data.diary = data.diary.filter { keep.contains($0.key) }
    }

    func toggleEaten(_ kind: MealKind) {
        guard let planned = data.day?[kind], let dish = recipe(planned.recipeID) else { return }
        let key = "meal:\(kind.rawValue):\(dish.id)"
        if planned.eaten {
            setDiaryToday(diaryToday.filter { $0.id != key })
        } else {
            let entry = DiaryEntry(id: key, name: dish.name, kcal: dish.kcal, protein: dish.protein, fat: dish.fat, carbs: dish.carbs, meal: kind, recipeID: dish.id)
            setDiaryToday(diaryToday.filter { $0.id != key } + [entry])
        }
        update(kind) { $0.eaten.toggle() }
    }

    func addDiary(_ entry: DiaryEntry) { setDiaryToday(diaryToday + [entry]) }

    func removeDiary(_ entry: DiaryEntry) {
        setDiaryToday(diaryToday.filter { $0.id != entry.id })
        if let kind = entry.meal, data.day?[kind]?.recipeID == entry.recipeID {
            update(kind) { $0.eaten = false }
        }
    }

    // MARK: - Холодильник и сброс

    func addFridge(name: String, amount: Double?, unit: String) {
        let item = FridgeItem(name: name, amount: amount, unit: amount == nil ? "" : unit)
        data.fridge = data.fridge.filter { !Shopping.same($0.name, name) } + [item]
    }

    /// Одной записью, а не по одному продукту: иначе файл сохранялся бы на каждый.
    func addRecognized(_ items: [RecognizedItem]) {
        let names = items.map(\.name)
        let added = items.map { FridgeItem(name: $0.name, amount: $0.amount, unit: $0.amount == nil ? "" : $0.unit) }
        data.fridge = data.fridge.filter { item in !names.contains { Shopping.same($0, item.name) } } + added
    }

    func resetAll() {
        skipped = [:]
        data = AppData()
    }
}
