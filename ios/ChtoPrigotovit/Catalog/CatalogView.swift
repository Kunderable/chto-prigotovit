import SwiftUI

struct CatalogFilters: Equatable {
    var meal: MealKind?
    var goal: Goal?
    var maxPrice: Int?
    var maxTime = 999
    var cuisine: String?

    var activeCount: Int { [goal != nil, maxPrice != nil, maxTime < 999, cuisine != nil].filter { $0 }.count }
}

/// Каталог: поиск, приём пищи на виду, остальные фильтры — в шторке.
struct CatalogView: View {
    @Environment(AppModel.self) private var model
    @State private var query = ""
    @State private var filters = CatalogFilters()
    @State private var showFilters = false
    @Namespace private var zoom

    var body: some View {
        let list = matches
        NavigationStack {
            List {
                Section {
                    Picker("Приём пищи", selection: $filters.meal.animation(.snappy)) {
                        Text("Всё").tag(MealKind?.none)
                        ForEach(MealKind.allCases) { Text($0 == .breakfast ? "Завтраки" : $0 == .lunch ? "Обеды" : "Ужины").tag(MealKind?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                }
                Section {
                    ForEach(list) { recipe in
                        NavigationLink(value: recipe) { RecipeRow(recipe: recipe, zoom: zoom) }
                    }
                } header: {
                    Text("\(list.count) \(Format.plural(list.count, "рецепт", "рецепта", "рецептов"))")
                }
            }
            .overlay {
                if list.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
            .searchable(text: $query, prompt: "Блюдо или продукт")
            .navigationTitle("Рецепты")
            .navigationDestination(for: Recipe.self) { recipe in
                DishView(mode: .preview(recipe))
                    .navigationTransition(.zoom(sourceID: recipe.id, in: zoom))
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showFilters = true } label: {
                        Image(systemName: filters.activeCount > 0 ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                    .badge(filters.activeCount)
                    .accessibilityLabel(filters.activeCount > 0 ? "Фильтры, выбрано \(filters.activeCount)" : "Фильтры")
                }
            }
            .sheet(isPresented: $showFilters) {
                FiltersSheet(filters: $filters, count: { matches(for: $0).count })
            }
        }
    }

    private var matches: [Recipe] { matches(for: filters) }

    private func matches(for f: CatalogFilters) -> [Recipe] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let avoid = Set(model.data.prefs.avoid.map(\.rawValue))
        return model.recipes.filter { r in
            avoid.isDisjoint(with: r.tags)
                && (f.meal.map { r.meal.contains($0) } ?? true)
                && DishPicker.matchesGoalFilter(r, f.goal)
                && (f.maxPrice.map { (model.portionCost(r) ?? .max) <= $0 } ?? true)
                && (f.cuisine.map { r.cuisine == $0 } ?? true)
                && r.time <= f.maxTime
                && (q.isEmpty || r.name.lowercased().contains(q) || r.ingredients.contains { $0.n.lowercased().contains(q) })
        }
    }
}

struct RecipeRow: View {
    @Environment(AppModel.self) private var model
    let recipe: Recipe
    let zoom: Namespace.ID

    var body: some View {
        HStack(spacing: 14) {
            DishTile(recipe: recipe, size: 48)
                .matchedTransitionSource(id: recipe.id, in: zoom)
            VStack(alignment: .leading, spacing: 3) {
                Text(recipe.name)
                Text(meta).font(.footnote).foregroundStyle(.secondary).monospacedDigit()
                let labels = DishPicker.labels(recipe)
                if !labels.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(labels, id: \.self) { label in
                            Text(label).font(.caption2.weight(.semibold))
                                .padding(.horizontal, 7).padding(.vertical, 2)
                                .background(.green.opacity(0.14), in: Capsule())
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 2)
    }

    private var meta: String {
        var parts = ["\(recipe.kcal) ккал", "\(recipe.time) мин"]
        if let cost = model.portionCost(recipe) { parts.append("≈ \(Format.rub(cost))") }
        return parts.joined(separator: " · ")
    }
}

struct FiltersSheet: View {
    @Binding var filters: CatalogFilters
    let count: (CatalogFilters) -> Int
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Цель") {
                    Picker("Цель", selection: $filters.goal) {
                        Text("Любая").tag(Goal?.none)
                        ForEach([Goal.lose, .lowcarb, .protein]) { Text($0.title).tag(Goal?.some($0)) }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section("Цена порции") {
                    Picker("Цена", selection: $filters.maxPrice) {
                        Text("Любая").tag(Int?.none)
                        ForEach(Pricing.steps, id: \.self) { Text("до \($0) ₽").tag(Int?.some($0)) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Время") {
                    Picker("Время", selection: $filters.maxTime) {
                        ForEach(Catalog.times, id: \.value) { Text($0.value >= 999 ? "любое" : $0.title).tag($0.value) }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Picker("Кухня", selection: $filters.cuisine) {
                        Text("Все кухни").tag(String?.none)
                        ForEach(Catalog.cuisines, id: \.id) { Text($0.id.capitalized).tag(String?.some($0.id)) }
                    }
                }
            }
            .navigationTitle("Фильтры")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Сбросить") { withAnimation { filters = CatalogFilters(meal: filters.meal) } }
                        .disabled(filters.activeCount == 0)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Показать \(count(filters))") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
