import Foundation
import Observation
import os

/// Состояние приложения и все действия пользователя. Данные хранятся в JSON-файле на устройстве.
@Observable
final class AppModel {
    let recipes: [Recipe]
    let pricing: Pricing
    private let index: [String: Recipe]
    private let storeURL: URL?
    private static let log = Logger(subsystem: "ru.chtoprigotovit.app", category: "store")

    var data: AppData { didSet { if data != oldValue { save() } } }
    /// Блюда, которые пользователь пролистал кнопкой «Другое» сегодня, — чтобы не предлагать их снова.
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

    // MARK: - Справочные данные

    func recipe(_ id: String?) -> Recipe? { id.flatMap { index[$0] } }
    var norm: DailyNorm? { data.body.map { Nutrition.norm(body: $0, goal: data.prefs.goal) } }
    func target(_ meal: MealKind) -> Int? { norm.map { Int((Double($0.kcal) * meal.share).rounded()) } }
    func portionCost(_ r: Recipe) -> Int? { pricing.portionCost(r) }

    static func dayKey(_ date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    // MARK: - План на день

    /// До 11:00 — завтрак, до 16:00 — обед, дальше — ужин.
    static func mealByClock(_ date: Date = .now) -> MealKind {
        let hour = Calendar.current.component(.hour, from: date)
        if hour < 11 { return .breakfast }
        return hour < 16 ? .lunch : .dinner
    }

    /// Что показать крупно: текущий приём пищи, а если он съеден — следующий несъеденный.
    func focusMeal(_ date: Date = .now) -> (meal: MealKind, isNext: Bool) {
        let now = Self.mealByClock(date)
        let order = MealKind.allCases
        let next = order[order.firstIndex(of: now)!...].first { kind in
            guard let m = data.day?[kind] else { return false }
            return !m.eaten
        }
        return (next ?? now, next != nil && next != now)
    }

    private func context() -> PickContext {
        var targets: [MealKind: Int] = [:]
        for kind in MealKind.allCases { targets[kind] = target(kind) }
        return PickContext(recipes: recipes, prefs: data.prefs, disliked: Set(data.disliked), liked: Set(data.liked),
                           fridge: data.fridge, recentIDs: Set(data.history.suffix(6).map(\.recipeID)), targetKcal: targets)
    }

    private func otherIDs(_ day: DayPlan, except kind: MealKind) -> Set<String> {
        Set(MealKind.allCases.filter { $0 != kind }.compactMap { day[$0]?.recipeID })
    }

    /// Гарантирует план на сегодня: три приёма пищи без повторов.
    func ensureDay(now: Date = .now) {
        let date = Self.dayKey(now)
        var day = data.day?.date == date ? data.day! : DayPlan(date: date)
        var changed = data.day != day
        var ctx = context()
        for kind in MealKind.allCases {
            if let m = day[kind], recipe(m.recipeID) != nil, m.cooked || !data.disliked.contains(m.recipeID) { continue }
            ctx.skipped = skipped[kind] ?? []
            var rng = SeededGenerator(seed: date + kind.rawValue)
            let dish = DishPicker.pick(meal: kind, exclude: otherIDs(day, except: kind), ctx: ctx, using: &rng)
            day[kind] = dish.map { PlannedMeal(recipeID: $0.id, portions: data.prefs.portions) }
            changed = true
        }
        if changed { data.day = day }
    }

    func put(_ recipeID: String, into kind: MealKind) {
        ensureDay()
        guard var day = data.day else { return }
        // уже съеденное остаётся в дневнике, даже если блюдо в плане заменили
        day[kind] = PlannedMeal(recipeID: recipeID, portions: data.prefs.portions)
        data.day = day
    }

    @discardableResult
    func reroll(_ kind: MealKind) -> Bool {
        guard let day = data.day, let current = day[kind]?.recipeID else { return false }
        skipped[kind, default: []].insert(current)
        var ctx = context()
        ctx.skipped = skipped[kind] ?? []
        var rng = SystemRandomNumberGenerator()
        guard let dish = DishPicker.pick(meal: kind, exclude: otherIDs(day, except: kind).union([current]), ctx: ctx, using: &rng) else { return false }
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

    /// План под новые настройки: съеденное и приготовленное остаётся, остальное подберётся заново.
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
        guard let m = data.day?[kind], let r = recipe(m.recipeID) else { return [] }
        return Shopping.rows(r, plan: m, fridge: data.fridge)
    }

    var dayShoppingRows: [ShoppingRow] {
        Shopping.merge(MealKind.allCases.compactMap { kind in
            guard let m = data.day?[kind], !m.cooked else { return nil }
            return rows(kind)
        })
    }

    /// Возвращает, что добавилось в холодильник.
    @discardableResult
    func cook(_ kind: MealKind) -> [String] {
        guard let m = data.day?[kind], let r = recipe(m.recipeID) else { return [] }
        let after = Shopping.fridgeAfterCooking(r, plan: m, fridge: data.fridge)
        data.fridge = after.fridge
        data.history = Array((data.history + [HistoryItem(recipeID: r.id, name: r.name, date: Self.dayKey())]).suffix(60))
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

    /// «Съел»: одна порция блюда попадает в дневник или убирается из него.
    func toggleEaten(_ kind: MealKind) {
        guard let m = data.day?[kind], let r = recipe(m.recipeID) else { return }
        let key = "meal:\(kind.rawValue):\(r.id)"
        if m.eaten {
            setDiaryToday(diaryToday.filter { $0.id != key })
        } else {
            let entry = DiaryEntry(id: key, name: r.name, kcal: r.kcal, p: r.p, f: r.f, c: r.c, meal: kind, recipeID: r.id)
            setDiaryToday(diaryToday.filter { $0.id != key } + [entry])
        }
        update(kind) { $0.eaten.toggle() }
    }

    func addDiary(_ entry: DiaryEntry) { setDiaryToday(diaryToday + [entry]) }

    func removeDiary(_ entry: DiaryEntry) {
        setDiaryToday(diaryToday.filter { $0.id != entry.id })
        // если блюдо всё ещё стоит в плане, снимаем у него отметку «съедено»
        if let kind = entry.meal, data.day?[kind]?.recipeID == entry.recipeID {
            update(kind) { $0.eaten = false }
        }
    }

    // MARK: - Холодильник и сброс

    func addFridge(name: String, amount: Double?, unit: String) {
        let item = FridgeItem(name: name, amount: amount, unit: amount == nil ? "" : unit)
        data.fridge = data.fridge.filter { !Shopping.same($0.name, name) } + [item]
    }

    func resetAll() {
        skipped = [:]
        data = AppData()
    }
}
