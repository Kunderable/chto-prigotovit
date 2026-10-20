import SwiftUI

/// Первый запуск: три коротких шага вместо одной длинной анкеты.
struct OnboardingView: View {
    @Environment(AppModel.self) private var model
    @State private var step = 0
    @State private var forward = true
    @State private var prefs = Prefs()
    @State private var body_ = BodyDraft()
    @State private var error: String?

    private let titles = [
        ("Что ты любишь?", "Выбери кухни — блюда будут из них."),
        ("Как ты ешь?", "Цель, ограничения и сколько времени готов готовить."),
        ("Твоя норма", "Вес, рост и возраст нужны для подсчёта КБЖУ. Можно пропустить."),
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    switch step {
                    case 0: cuisinesStep
                    case 1: habitsStep
                    default: bodyStep
                    }
                }
                .id(step)
                .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                        removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
                footer
            }
            .background { AmbientBackground(hue: 18) }
            .toolbar {
                ToolbarItem(placement: .principal) { progress }
                if step > 0 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { go(step - 1) } label: { Image(systemName: "chevron.left") }.accessibilityLabel("Назад")
                    }
                }
                if step == titles.count - 1 {
                    ToolbarItem(placement: .topBarTrailing) { Button("Пропустить") { finish(withBody: false) } }
                }
            }
        }
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<titles.count, id: \.self) { i in
                Capsule()
                    .fill(i <= step ? Color.paprika : Color.secondary.opacity(0.25))
                    .frame(width: i == step ? 22 : 7, height: 7)
            }
        }
        .animation(.bouncy, value: step)
        .accessibilityLabel("Шаг \(step + 1) из \(titles.count)")
    }

    private func header(_ i: Int) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titles[i].0).font(.largeTitle.bold())
            Text(titles[i].1).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 24)
    }

    private var cuisinesStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header(0)
                FlowLayout(spacing: 8) {
                    ForEach(Catalog.cuisines, id: \.id) { cuisine in
                        let on = prefs.cuisines.contains(cuisine.id)
                        Button {
                            withAnimation(.snappy) {
                                if on { prefs.cuisines.removeAll { $0 == cuisine.id } } else { prefs.cuisines.append(cuisine.id) }
                            }
                        } label: {
                            Text(cuisine.id.capitalized)
                                .font(.callout.weight(.medium))
                                .padding(.horizontal, 15).padding(.vertical, 9)
                                .background(on ? Color.primary : Color.secondary.opacity(0.14), in: Capsule())
                                .foregroundStyle(on ? Color(uiColor: .systemBackground) : .primary)
                        }
                        .buttonStyle(.plain)
                        .sensoryFeedback(.selection, trigger: on)
                    }
                }
                .padding(.horizontal, 20)
            }
        }
    }

    private var habitsStep: some View {
        Form {
            Section { EmptyView() } header: { header(1).padding(.horizontal, -20).textCase(nil).foregroundStyle(.primary) }
            Section("Цель") {
                Picker("Цель", selection: $prefs.goal) { ForEach(Goal.allCases) { Text($0.title).tag($0) } }
                    .pickerStyle(.inline).labelsHidden()
            }
            Section("Не ем") {
                ForEach(Restriction.allCases) { item in
                    Toggle(item.title, isOn: Binding {
                        prefs.avoid.contains(item)
                    } set: { on in
                        if on { prefs.avoid.append(item) } else { prefs.avoid.removeAll { $0 == item } }
                    })
                }
            }
            Section("Время у плиты") {
                Picker("Время", selection: $prefs.maxTime) {
                    ForEach(Catalog.times, id: \.value) { Text($0.title).tag($0.value) }
                }
                .pickerStyle(.segmented)
            }
            Section("Готовлю на") {
                Picker("Порции", selection: $prefs.portions) {
                    ForEach(1...4, id: \.self) { Text($0 == 4 ? "4+" : "\($0)").tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .scrollContentBackground(.hidden)
    }

    private var bodyStep: some View {
        Form {
            Section { EmptyView() } header: { header(2).padding(.horizontal, -20).textCase(nil).foregroundStyle(.primary) }
            BodyFields(draft: $body_)
            if let error { Text(error).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        let last = step == titles.count - 1
        return Button {
            if last { finish(withBody: !body_.isEmpty) } else { go(step + 1) }
        } label: {
            Text(prefs.cuisines.isEmpty ? "Выбери хотя бы одну кухню" : last ? "Готово" : "Далее")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.extraLarge)
        .disabled(prefs.cuisines.isEmpty)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    private func go(_ next: Int) {
        forward = next > step
        withAnimation(.smooth(duration: 0.4)) { step = next }
    }

    private func finish(withBody: Bool) {
        var body: BodyData?
        if withBody {
            do { body = try body_.parsed() } catch { self.error = error.message; return }
        }
        model.data.prefs = prefs
        model.data.body = body
        model.data.day = nil
        model.ensureDay()
        model.data.onboarded = true
    }
}

/// Раскладка «тегов»: элементы переносятся на следующую строку, когда не помещаются.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows = [Row()]
        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            if rows[rows.count - 1].width + size.width > width, !rows[rows.count - 1].items.isEmpty { rows.append(Row()) }
            rows[rows.count - 1].items.append(index)
            rows[rows.count - 1].width += size.width + spacing
            rows[rows.count - 1].height = max(rows[rows.count - 1].height, size.height)
        }
        return rows
    }
}
