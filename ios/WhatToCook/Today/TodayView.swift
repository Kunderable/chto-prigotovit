import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Namespace private var zoom
    @State private var sheet: TodaySheet?
    @State private var now = Date.now

    private let clock = Timer.publish(every: 600, on: .main, in: .common).autoconnect()

    var body: some View {
        @Bindable var router = router
        let focus = model.focusMeal(now)
        NavigationStack(path: $router.todayPath) {
            ScrollView {
                VStack(spacing: 16) {
                    Text(Format.sentence(now.formatted(.dateTime.weekday(.wide).day().month(.wide))))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, -8)
                    SummaryCard { sheet = .body }
                    HeroCard(kind: focus.meal, isNext: focus.isNext, zoom: zoom)
                    otherMeals(except: focus.meal)
                    quickActions
                }
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
            .background { AmbientBackground(hue: heroHue(focus.meal)) }
            .navigationTitle("Сегодня")
            .navigationDestination(for: MealKind.self) { kind in
                DishView(mode: .planned(kind))
                    .navigationTransition(.zoom(sourceID: kind, in: zoom))
            }
            .sheet(item: $sheet) { sheet in
                switch sheet {
                case .diary: DiarySheet()
                case .shopping: ShoppingSheet()
                case .body: BodyForm()
                }
            }
        }
        .onAppear { model.ensureDay() }
        .onReceive(clock) { now = $0; model.ensureDay(now: $0) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { now = .now; model.ensureDay() }
        }
    }

    private func heroHue(_ kind: MealKind) -> Double {
        model.recipe(model.data.day?[kind]?.recipeID).map { Catalog.hue(for: $0.cuisine) } ?? 32
    }

    private func otherMeals(except focus: MealKind) -> some View {
        VStack(spacing: 0) {
            let kinds = MealKind.allCases.filter { $0 != focus }
            ForEach(kinds) { kind in
                MealRow(kind: kind, zoom: zoom)
                if kind != kinds.last { Divider().padding(.leading, 70) }
            }
        }
        .card(22)
    }

    private var quickActions: some View {
        let rows = model.dayShoppingRows
        let diary = model.diaryToday.count
        return HStack(spacing: 12) {
            QuickButton(icon: "cart", title: "Купить",
                        subtitle: rows.isEmpty ? "список пуст" : "\(rows.count) \(Format.plural(rows.count, "продукт", "продукта", "продуктов"))") { sheet = .shopping }
            QuickButton(icon: "list.bullet.clipboard", title: "Дневник",
                        subtitle: diary == 0 ? "пусто" : "\(diary) \(Format.plural(diary, "запись", "записи", "записей"))") { sheet = .diary }
        }
    }
}

enum TodaySheet: String, Identifiable {
    case diary, shopping, body
    var id: String { rawValue }
}

struct SummaryCard: View {
    @Environment(AppModel.self) private var model
    var onSetup: () -> Void

    var body: some View {
        let eaten = model.eatenToday
        if let norm = model.norm {
            let left = norm.kcal - eaten.kcal
            HStack(spacing: 16) {
                MacroRings(eaten: eaten, norm: norm)
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(eaten.kcal)")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .contentTransition(.numericText(value: Double(eaten.kcal)))
                        Text("из \(norm.kcal) ккал").font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        Text(left >= 0 ? "ещё \(left)" : "+\(-left)")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(left >= 0 ? .green : .red)
                    }
                    ProgressView(value: min(Double(eaten.kcal), Double(norm.kcal)), total: Double(norm.kcal))
                        .tint(left >= 0 ? .paprika : .red)
                    HStack(spacing: 10) {
                        macro("Б", eaten.protein, norm.protein, .protein)
                        macro("Ж", eaten.fat, norm.fat, .fat)
                        macro("У", eaten.carbs, norm.carbs, .carbs)
                    }
                }
            }
            .padding(16)
            .card()
            .animation(.smooth, value: eaten)
        } else {
            Button(action: onSetup) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Посчитать норму КБЖУ").font(.headline)
                        Text(eaten.kcal > 0 ? "Сегодня съедено \(eaten.kcal) ккал" : "Вес, рост и возраст — меньше минуты")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.paprika)
                }
                .padding(18)
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    private func macro(_ label: String, _ value: Int, _ total: Int, _ color: Color) -> some View {
        HStack(spacing: 4) {
            MacroDot(color: color)
            Text("\(value)").fontWeight(.semibold).foregroundStyle(.primary)
            Text("/\u{2009}\(total)\u{2009}\(label)").foregroundStyle(.secondary)
        }
        .font(.footnote)
        .lineLimit(1)
        .fixedSize()
        .monospacedDigit()
    }
}

struct HeroCard: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    let kind: MealKind
    let isNext: Bool
    let zoom: Namespace.ID

    var body: some View {
        let plan = model.data.day?[kind]
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text((isNext ? "Дальше " : "Сейчас ") + kind.title.lowercased())
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .kerning(0.6)
                    .foregroundStyle(Color.paprika)
                Spacer()
                if let target = model.target(kind) {
                    Text("цель ≈ \(target) ккал").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if let plan, let recipe = model.recipe(plan.recipeID) {
                Button { router.todayPath = [kind] } label: {
                    HStack(spacing: 16) {
                        DishTile(recipe: recipe, size: 92)
                            .matchedTransitionSource(id: kind, in: zoom)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(recipe.name)
                                .font(.title2.bold())
                                .multilineTextAlignment(.leading)
                                .foregroundStyle(.primary)
                            Text(facts(recipe)).font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                            if !DishPicker.leftoverHits(recipe, fridge: model.data.fridge).isEmpty {
                                Text("доедаем остатки").font(.caption.weight(.semibold))
                                    .padding(.horizontal, 8).padding(.vertical, 3)
                                    .background(.green.opacity(0.14), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }
                .buttonStyle(.plain)

                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { router.todayPath = [kind] } label: {
                            Text("Готовить").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        .controlSize(.large)

                        Button {
                            withAnimation(.smooth) { _ = model.reroll(kind) }
                        } label: {
                            Image(systemName: "dice")
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(plan.eaten || plan.cooked)
                        .accessibilityLabel("Другое блюдо")

                        Button {
                            withAnimation(.snappy) { model.toggleShopping(kind) }
                        } label: {
                            Image(systemName: plan.inShopping ? "cart.fill" : "cart.badge.plus")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .disabled(plan.eaten || plan.cooked)
                        .sensoryFeedback(.selection, trigger: plan.inShopping)
                        .accessibilityLabel(plan.inShopping ? "Убрать из покупок" : "Добавить в покупки")

                        EatButton(kind: kind, eaten: plan.eaten)
                    }
                }
            } else {
                Text("Под твои фильтры ничего не нашлось.").foregroundStyle(.secondary)
                Button("Подобрать ещё раз") { model.ensureDay() }.buttonStyle(.glass)
            }
        }
        .padding(20)
        .glassEffect(.regular.tint(tint(plan).opacity(0.12)), in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .overlay {
            if plan?.eaten == true {
                RoundedRectangle(cornerRadius: 32, style: .continuous).strokeBorder(.green, lineWidth: 2)
            }
        }
    }

    private func tint(_ plan: PlannedMeal?) -> Color {
        model.recipe(plan?.recipeID).map { Color.cuisine($0.cuisine) } ?? .paprika
    }

    private func facts(_ recipe: Recipe) -> String {
        var parts = ["\(recipe.kcal) ккал", "\(recipe.time) мин"]
        if let cost = model.portionCost(recipe) { parts.append("≈ \(Format.rub(cost))") }
        return parts.joined(separator: " · ")
    }
}

struct EatButton: View {
    @Environment(AppModel.self) private var model
    let kind: MealKind
    let eaten: Bool

    var body: some View {
        Group {
            if eaten {
                Button(action: toggle) { Image(systemName: "checkmark") }
                    .buttonStyle(.glassProminent)
                    .tint(.green)
            } else {
                Button(action: toggle) { Image(systemName: "checkmark") }
                    .buttonStyle(.glass)
            }
        }
        .controlSize(.large)
        .symbolEffect(.bounce, value: eaten)
        .sensoryFeedback(.success, trigger: eaten) { _, new in new }
        .accessibilityLabel(eaten ? "Убрать из дневника" : "Записать в дневник")
    }

    private func toggle() { withAnimation(.snappy) { model.toggleEaten(kind) } }
}

struct MealRow: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    let kind: MealKind
    let zoom: Namespace.ID

    var body: some View {
        if let plan = model.data.day?[kind], let recipe = model.recipe(plan.recipeID) {
            HStack(spacing: 12) {
                Button { router.todayPath = [kind] } label: {
                    HStack(spacing: 12) {
                        DishTile(recipe: recipe, size: 40)
                            .matchedTransitionSource(id: kind, in: zoom)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(kind.title).font(.caption.weight(.semibold)).textCase(.uppercase).foregroundStyle(.secondary)
                            Text(recipe.name).lineLimit(1).foregroundStyle(plan.eaten ? .secondary : .primary)
                        }
                        Spacer(minLength: 8)
                        Text("\(recipe.kcal) ккал").font(.subheadline).foregroundStyle(.secondary).monospacedDigit()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button { withAnimation(.snappy) { model.toggleEaten(kind) } } label: {
                    Image(systemName: plan.eaten ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(plan.eaten ? .green : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
                .sensoryFeedback(.success, trigger: plan.eaten) { _, new in new }
                .accessibilityLabel(plan.eaten ? "\(kind.title): убрать из дневника" : "\(kind.title): записать в дневник")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }
}

struct QuickButton: View {
    let icon: String
    let title: String
    let subtitle: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.title3).foregroundStyle(Color.paprika)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.headline)
                    Text(subtitle).font(.footnote).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .card(22)
        }
        .buttonStyle(.plain)
    }
}
