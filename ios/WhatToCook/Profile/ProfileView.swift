import SwiftUI

/// Профиль в духе «Настроек»: норма КБЖУ сверху, предпочтения списком.
struct ProfileView: View {
    @Environment(AppModel.self) private var model
    @State private var editingBody = false
    @State private var confirmReset = false

    var body: some View {
        let prefs = model.data.prefs
        NavigationStack {
            List {
                Section { normSection }
                Section("Предпочтения") {
                    NavigationLink { GoalEditor() } label: { row("Цель", prefs.goal.title) }
                    NavigationLink { CuisineEditor() } label: {
                        row("Кухни", prefs.cuisines.count == Catalog.cuisines.count ? "все" : "\(prefs.cuisines.count) из \(Catalog.cuisines.count)")
                    }
                    NavigationLink { AvoidEditor() } label: {
                        row("Не ем", prefs.avoid.isEmpty ? "нет" : prefs.avoid.map { $0.title.lowercased() }.joined(separator: ", "))
                    }
                    Picker("Время у плиты", selection: binding(\.maxTime)) {
                        ForEach(Catalog.times, id: \.value) { Text($0.title).tag($0.value) }
                    }
                    Picker("Готовлю на", selection: binding(\.portions)) {
                        ForEach(1...4, id: \.self) { Text("\($0) \(Format.plural($0, "персону", "персоны", "персон"))").tag($0) }
                    }
                }
                let history = model.data.history.suffix(5).reversed()
                if !history.isEmpty {
                    Section("Недавно готовил") {
                        ForEach(Array(history.enumerated()), id: \.offset) { _, item in
                            row(item.name, String(item.date.suffix(5)).split(separator: "-").reversed().joined(separator: "."))
                        }
                    }
                }
                Section {
                    if !model.data.disliked.isEmpty {
                        Button("Вернуть скрытые блюда (\(model.data.disliked.count))") { model.data.disliked = [] }
                    }
                    Button("Сбросить все данные", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Всё хранится только на этом устройстве.")
                }
            }
            .navigationTitle("Профиль")
            .sheet(isPresented: $editingBody) { BodyForm() }
            .confirmationDialog("Стереть все данные?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Стереть", role: .destructive) { model.resetAll() }
            } message: {
                Text("Пропадут план, дневник, холодильник и настройки.")
            }
        }
    }

    @ViewBuilder
    private var normSection: some View {
        if let norm = model.norm, let body = model.data.body {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Норма в день").font(.caption.weight(.bold)).textCase(.uppercase).kerning(0.6).foregroundStyle(Color.paprika)
                    Spacer()
                    Button("Изменить") { editingBody = true }.font(.subheadline.weight(.semibold))
                }
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(norm.kcal)").font(.system(size: 44, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("ккал").foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    macro(norm.protein, "белки", .protein)
                    macro(norm.fat, "жиры", .fat)
                    macro(norm.carbs, "углеводы", .carbs)
                }
                Text("\(goalNote(model.data.prefs.goal)). \(body.sex.title), \(body.age) лет, \(Int(body.height)) см, \(Format.amount(body.weight, "")) кг.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .padding(.vertical, 6)
        } else {
            Button { editingBody = true } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Посчитать норму КБЖУ").font(.headline)
                    Text("Блюда будут подбираться под неё, а «Сегодня» покажет прогресс").font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func goalNote(_ goal: Goal) -> String {
        switch goal {
        case .normal: "Поддержание веса"
        case .lose: "Похудение: минус 17% калорий"
        case .protein: "Больше белка: 2 г на кг веса"
        case .lowcarb: "Мало углеводов: до \(Nutrition.lowcarbDayCarbs) г в день"
        }
    }

    private func macro(_ value: Int, _ label: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("\(value)").font(.system(.title3, design: .rounded, weight: .bold)).monospacedDigit()
                Text("г").font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) { MacroDot(color: color); Text(label).font(.caption).foregroundStyle(.secondary) }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(value).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func binding<T>(_ keyPath: WritableKeyPath<Prefs, T>) -> Binding<T> {
        Binding { model.data.prefs[keyPath: keyPath] } set: { value in
            var prefs = model.data.prefs
            prefs[keyPath: keyPath] = value
            model.updatePrefs(prefs)
        }
    }
}

struct GoalEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(Goal.allCases) { goal in
                Button {
                    var prefs = model.data.prefs
                    prefs.goal = goal
                    withAnimation(.snappy) { model.updatePrefs(prefs) }
                } label: {
                    HStack {
                        Text(goal.title).foregroundStyle(.primary)
                        Spacer()
                        if model.data.prefs.goal == goal {
                            Image(systemName: "checkmark").foregroundStyle(Color.paprika).transition(.scale.combined(with: .opacity))
                        }
                    }
                }
            }
        }
        .navigationTitle("Цель")
        .sensoryFeedback(.selection, trigger: model.data.prefs.goal)
    }
}

struct CuisineEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let selected = Set(model.data.prefs.cuisines)
        List {
            Section {
                ForEach(Catalog.cuisines, id: \.id) { cuisine in
                    Button { toggle(cuisine.id) } label: {
                        HStack {
                            Text(cuisine.id.capitalized).foregroundStyle(.primary)
                            Spacer()
                            if selected.contains(cuisine.id) {
                                Image(systemName: "checkmark").foregroundStyle(Color.paprika)
                            }
                        }
                    }
                }
            } footer: {
                Text("Блюда дня подбираются из этих кухонь. Если под фильтры ничего не найдётся, приложение возьмёт другие.")
            }
        }
        .navigationTitle("Кухни")
        .toolbar {
            Button(selected.count == Catalog.cuisines.count ? "Снять все" : "Выбрать все") {
                var prefs = model.data.prefs
                prefs.cuisines = selected.count == Catalog.cuisines.count ? [] : Catalog.cuisines.map(\.id)
                model.updatePrefs(prefs)
            }
        }
    }

    private func toggle(_ id: String) {
        var prefs = model.data.prefs
        if prefs.cuisines.contains(id) { prefs.cuisines.removeAll { $0 == id } } else { prefs.cuisines.append(id) }
        model.updatePrefs(prefs)
    }
}

struct AvoidEditor: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List {
            ForEach(Restriction.allCases) { item in
                Toggle(item.title, isOn: Binding {
                    model.data.prefs.avoid.contains(item)
                } set: { on in
                    var prefs = model.data.prefs
                    if on { prefs.avoid.append(item) } else { prefs.avoid.removeAll { $0 == item } }
                    model.updatePrefs(prefs)
                })
            }
        }
        .navigationTitle("Не ем")
    }
}

/// Пол, возраст, рост, вес и активность — для нормы КБЖУ.
struct BodyForm: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var draft = BodyDraft()
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                BodyFields(draft: $draft, error: error)
                if model.data.body != nil {
                    Section {
                        Button("Удалить мои данные", role: .destructive) { model.setBody(nil); dismiss() }
                    }
                }
            }
            .navigationTitle("Мои данные")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Сохранить", action: save) }
            }
            .onAppear { if let body = model.data.body { draft = BodyDraft(body) } }
        }
        .presentationDetents([.large])
    }

    private func save() {
        do {
            model.setBody(try draft.parsed())
            dismiss()
        } catch {
            self.error = error.message
        }
    }
}

struct BodyDraft {
    var sex: Sex = .female
    var age = ""
    var height = ""
    var weight = ""
    var activity = 1.375

    init() {}
    init(_ body: BodyData) {
        sex = body.sex
        age = String(body.age)
        height = Format.amount(body.height, "")
        weight = Format.amount(body.weight, "")
        activity = body.activity
    }

    var isEmpty: Bool { [age, height, weight].allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty } }

    func parsed() throws(Nutrition.BodyInputError) -> BodyData {
        try Nutrition.parseBody(sex: sex, age: age, height: height, weight: weight, activity: activity)
    }
}

struct BodyFields: View {
    @Binding var draft: BodyDraft
    var error: String?

    var body: some View {
        Section {
            Picker("Пол", selection: $draft.sex) {
                ForEach(Sex.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .listRowBackground(Color.clear)
            .listRowInsets(EdgeInsets())
        }
        Section {
            field("Возраст", "лет", $draft.age, placeholder: "30")
            field("Рост", "см", $draft.height, placeholder: "170")
            field("Вес", "кг", $draft.weight, placeholder: "70")
            Picker("Активность", selection: $draft.activity) {
                ForEach(Nutrition.activity, id: \.value) { Text($0.title).tag($0.value) }
            }
            .pickerStyle(.navigationLink)
        } footer: {
            if let error {
                Label(error, systemImage: "exclamationmark.circle").foregroundStyle(.red)
            }
        }
    }

    private func field(_ title: String, _ unit: String, _ text: Binding<String>, placeholder: String) -> some View {
        HStack {
            Text(title)
            Spacer()
            TextField(placeholder, text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 90)
            Text(unit).foregroundStyle(.secondary)
        }
    }
}
