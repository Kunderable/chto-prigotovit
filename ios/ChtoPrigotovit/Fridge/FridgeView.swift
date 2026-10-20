import SwiftUI

/// Холодильник: остатки после готовки и то, что добавил сам.
struct FridgeView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = "г"
    @FocusState private var nameFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                if model.data.fridge.isEmpty {
                    ContentUnavailableView {
                        Label("Пока пусто", systemImage: "refrigerator")
                    } description: {
                        Text("Когда приготовишь блюдо, остатки упаковок появятся здесь сами. Блюда, где их можно доесть, будут попадаться чаще.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(model.data.fridge) { item in
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text(item.amount == nil ? "есть" : Format.amount(item.amount, item.unit))
                                    .foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .onDelete { model.data.fridge.remove(atOffsets: $0) }
                    }
                }
                Section("Добавить") {
                    TextField("Например, сливки", text: $name).focused($nameFocused).submitLabel(.done).onSubmit(add)
                    HStack {
                        TextField("Количество", text: $amount).keyboardType(.decimalPad)
                        Picker("Единица", selection: $unit) {
                            ForEach(Catalog.units, id: \.self) { Text($0) }
                        }
                        .labelsHidden()
                        .fixedSize()
                    }
                    Button("Добавить в холодильник", action: add)
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .navigationTitle("Холодильник")
            .toolbar { if !model.data.fridge.isEmpty { EditButton() } }
            .animation(.smooth, value: model.data.fridge)
        }
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let value = Double(amount.replacingOccurrences(of: ",", with: ".")).flatMap { $0 > 0 ? $0 : nil }
        model.addFridge(name: String(trimmed.prefix(60)), amount: value, unit: unit)
        name = ""
        amount = ""
        nameFocused = false
    }
}
