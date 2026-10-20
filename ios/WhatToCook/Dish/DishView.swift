import SwiftUI
import UIKit

/// Экран блюда — один и тот же для блюда из плана и для рецепта из каталога.
/// Сверху суть (КБЖУ, цена, порции, главное действие), ниже вкладки «Продукты» и «Приготовление».
struct DishView: View {
    enum Mode: Hashable {
        case planned(MealKind)
        case preview(Recipe)
    }

    enum Section: String, CaseIterable, Identifiable {
        case ingredients = "Продукты", steps = "Приготовление"
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router
    let mode: Mode
    @State private var section: Section = .ingredients
    @State private var previewPortions: Int?
    @State private var copied = false
    @State private var cookedNote: String?

    private var kind: MealKind? { if case .planned(let meal) = mode { meal } else { nil } }
    private var plan: PlannedMeal? { kind.flatMap { model.data.day?[$0] } }
    private var recipe: Recipe? {
        switch mode {
        case .planned: model.recipe(plan?.recipeID)
        case .preview(let recipe): recipe
        }
    }
    private var portions: Int { plan?.portions ?? previewPortions ?? model.data.prefs.portions }

    var body: some View {
        if let recipe {
            ScrollView {
                VStack(spacing: 18) {
                    header(recipe)
                    StatGrid(recipe: recipe)
                    controls(recipe)
                    Picker("Раздел", selection: $section.animation(.snappy)) {
                        ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    Group {
                        switch section {
                        case .ingredients: ingredients(recipe)
                        case .steps: steps(recipe)
                        }
                    }
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                }
                .padding(.horizontal)
                .padding(.bottom, 32)
            }
            .background { AmbientBackground(hue: Catalog.hue(for: recipe.cuisine)) }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sensoryFeedback(.success, trigger: plan?.eaten ?? false) { _, new in new }
        } else {
            ContentUnavailableView("Блюдо не найдено", systemImage: "questionmark.circle")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let kind, let plan {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button { withAnimation(.smooth) { _ = model.reroll(kind) } } label: { Image(systemName: "dice") }
                    .accessibilityLabel("Другое блюдо")
                    .disabled(plan.eaten || plan.cooked)
                Button { withAnimation(.smooth) { model.neverAgain(kind) } } label: { Image(systemName: "eye.slash") }
                    .accessibilityLabel("Больше не предлагать")
                    .disabled(plan.eaten || plan.cooked)
            }
        }
    }

    private func header(_ recipe: Recipe) -> some View {
        VStack(spacing: 8) {
            DishTile(recipe: recipe, size: 112).padding(.bottom, 6)
            Text(kicker(recipe))
                .font(.caption.weight(.bold)).kerning(0.6).textCase(.uppercase)
                .foregroundStyle(Color.paprika)
            Text(recipe.name)
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(facts(recipe)).font(.subheadline).foregroundStyle(.secondary)
            let hits = DishPicker.leftoverHits(recipe, fridge: model.data.fridge)
            if !hits.isEmpty {
                Text("доедаем: " + hits.map { $0.name.lowercased() }.joined(separator: ", "))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.green.opacity(0.14), in: Capsule())
                    .foregroundStyle(.green)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    private func kicker(_ recipe: Recipe) -> String {
        if let kind { return kind.title }
        return recipe.meal.map(\.title).joined(separator: " · ")
    }

    private func facts(_ recipe: Recipe) -> String {
        var parts = [recipe.cuisine.capitalized, "\(recipe.time) мин"]
        if let cost = model.portionCost(recipe) { parts.append("≈ \(Format.rub(cost)) за порцию") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Порции и главное действие

    private func controls(_ recipe: Recipe) -> some View {
        VStack(spacing: 14) {
            HStack {
                Text("Порций")
                Spacer()
                Stepper(value: portionsBinding, in: 1...Catalog.maxPortions) {
                    Text("\(portions)").font(.system(.body, design: .rounded, weight: .bold)).monospacedDigit()
                        .contentTransition(.numericText(value: Double(portions)))
                }
                .fixedSize()
            }
            if let kind, let plan {
                Button { withAnimation(.snappy) { model.toggleEaten(kind) } } label: {
                    Label(plan.eaten ? "Записано в дневник" : "Записать в дневник", systemImage: plan.eaten ? "checkmark" : "plus")
                        .frame(maxWidth: .infinity)
                        .symbolEffect(.bounce, value: plan.eaten)
                }
                .buttonStyle(.glassProminent)
                .tint(plan.eaten ? .green : .paprika)
                .controlSize(.large)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Готовить сегодня на").font(.footnote).foregroundStyle(.secondary)
                    GlassEffectContainer(spacing: 8) {
                        HStack(spacing: 8) {
                            ForEach(MealKind.allCases) { kind in
                                planButton(kind, recipe: recipe)
                            }
                        }
                    }
                }
            }
        }
        .padding(18)
        .card()
    }

    @ViewBuilder
    private func planButton(_ kind: MealKind, recipe recipe: Recipe) -> some View {
        let action = {
            model.put(recipe.id, into: kind)
            router.openPlanned(kind)
        }
        if recipe.meal.contains(kind) {
            Button(action: action) { Text(kind.title).frame(maxWidth: .infinity) }.buttonStyle(.glassProminent)
        } else {
            Button(action: action) { Text(kind.title).frame(maxWidth: .infinity) }.buttonStyle(.glass)
        }
    }

    private var portionsBinding: Binding<Int> {
        Binding {
            portions
        } set: { value in
            withAnimation(.snappy) {
                if let kind { model.update(kind) { $0.portions = value } } else { previewPortions = value }
            }
        }
    }

    // MARK: - Продукты

    @ViewBuilder
    private func ingredients(_ recipe: Recipe) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if let kind, let plan {
                let rows = model.rows(kind)
                rowsCard(rows.filter { !$0.isPantry }, kind: kind, plan: plan)
                let pantry = rows.filter(\.isPantry)
                if !pantry.isEmpty {
                    sectionTitle("Специи и масло", note: "Отметь, что есть дома, — приложение запомнит для всех рецептов")
                    rowsCard(pantry, kind: kind, plan: plan)
                }
            } else {
                let items = Shopping.scaled(recipe, portions: portions)
                plainCard(items.filter { !$0.isPantry })
                let pantry = items.filter(\.isPantry)
                if !pantry.isEmpty {
                    sectionTitle("Специи и масло", note: nil)
                    plainCard(pantry)
                }
            }

            if let kind, let plan, !plan.cooked {
                let rows = model.rows(kind)
                let toBuy = rows.filter { !$0.have }
                let cost = model.pricing.buyCost(rows)
                Button {
                    UIPasteboard.general.string = Shopping.listText(title: "Купить для «\(recipe.name)», \(plan.portions) порц.", rows: rows)
                    copied = true
                } label: {
                    Label(toBuy.isEmpty ? "Всё есть дома" : (copied ? "Скопировано" : "Скопировать список" + (cost > 0 ? " · ≈ \(Format.rub(cost))" : "")),
                          systemImage: copied ? "checkmark" : "doc.on.doc")
                        .frame(maxWidth: .infinity)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .disabled(toBuy.isEmpty)
                .sensoryFeedback(.success, trigger: copied)
            }
        }
    }

    private func rowsCard(_ rows: [ShoppingRow], kind: MealKind, plan: PlannedMeal) -> some View {
        VStack(spacing: 0) {
            ForEach(rows) { row in
                ingredientRow(row, kind: kind, plan: plan)
                if row.id != rows.last?.id { Divider().padding(.leading, 54) }
            }
        }
        .card(22)
    }

    private func plainCard(_ items: [Ingredient]) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack {
                    Text(item.name)
                    Spacer()
                    Text(Format.amount(item.amount, item.unit)).foregroundStyle(.secondary).monospacedDigit()
                }
                .padding(.horizontal, 16).padding(.vertical, 13)
                if index < items.count - 1 { Divider().padding(.leading, 16) }
            }
        }
        .card(22)
    }

    private func sectionTitle(_ title: String, note: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.headline)
            if let note { Text(note).font(.footnote).foregroundStyle(.secondary) }
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    private func ingredientRow(_ row: ShoppingRow, kind: MealKind, plan: PlannedMeal) -> some View {
        Button {
            withAnimation(.snappy) { model.toggleHave(row, in: kind) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: row.have ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(row.have ? .green : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                VStack(alignment: .leading, spacing: 2) {
                    Text(row.name).foregroundStyle(row.have ? .secondary : .primary)
                    if let note = note(row) {
                        Text(note.text).font(.footnote).foregroundStyle(note.ok ? .green : .secondary)
                    }
                }
                Spacer()
                Text(Format.amount(row.amount, row.unit)).foregroundStyle(.secondary).monospacedDigit()
            }
            .padding(.horizontal, 16).padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(row.have ? .isSelected : [])
    }

    private func note(_ row: ShoppingRow) -> (text: String, ok: Bool)? {
        if row.inFridge && row.fromFridge > 0 && row.toBuy > 0 {
            return ("в холодильнике \(Format.amount(row.fromFridge, row.unit)), докупить \(Format.amount(row.toBuy, row.unit))", true)
        }
        if row.inFridge && row.toBuy == 0 { return ("есть в холодильнике", true) }
        if row.isPantry && row.have { return ("есть дома", true) }
        if row.packs > 0 && !row.have {
            let left = row.leftover >= (Shopping.leftoverMin[row.unit] ?? 1) ? ", останется \(Format.amount(row.leftover, row.unit))" : ""
            return ("\(row.packs) уп. по \(Format.amount(row.packSize, row.unit))\(left)", false)
        }
        return nil
    }

    // MARK: - Приготовление

    private func steps(_ recipe: Recipe) -> some View {
        VStack(spacing: 12) {
            VStack(spacing: 0) {
                ForEach(Array(recipe.steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 14) {
                        Text("\(index + 1)")
                            .font(.system(.subheadline, design: .rounded, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(Color.paprika.opacity(0.14), in: Circle())
                            .foregroundStyle(Color.paprika)
                        Text(step).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(16)
                    if index < recipe.steps.count - 1 { Divider().padding(.leading, 58) }
                }
            }
            .card(22)

            if let kind, let plan {
                if !plan.cooked {
                    Button {
                        withAnimation(.smooth) {
                            let added = model.cook(kind)
                            cookedNote = added.isEmpty ? "Остатков нет" : "В холодильник: " + added.joined(separator: ", ")
                        }
                    } label: {
                        Label("Я приготовил", systemImage: "frying.pan").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                } else {
                    rating(kind, plan: plan)
                }
            }
        }
    }

    private func rating(_ kind: MealKind, plan: PlannedMeal) -> some View {
        VStack(spacing: 12) {
            if let cookedNote { Text(cookedNote).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center) }
            if plan.rated {
                Text("Спасибо! Учту при следующих подборах.").font(.subheadline).foregroundStyle(.secondary)
            } else {
                Text("Как получилось?").font(.headline)
                GlassEffectContainer(spacing: 10) {
                    HStack(spacing: 10) {
                        Button { withAnimation(.snappy) { model.rate(kind, good: true) } } label: {
                            Label("Вкусно", systemImage: "hand.thumbsup").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glassProminent)
                        Button { withAnimation(.snappy) { model.rate(kind, good: false) } } label: {
                            Label("Не моё", systemImage: "hand.thumbsdown").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.glass)
                    }
                    .controlSize(.large)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .card()
    }
}
