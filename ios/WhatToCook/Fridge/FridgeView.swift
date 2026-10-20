import SwiftUI

struct FridgeView: View {
    @Environment(AppModel.self) private var model
    @State private var name = ""
    @State private var amount = ""
    @State private var unit = "г"
    @FocusState private var nameFocused: Bool
    private let recognizer = FridgeRecognizer.fromBundle()

    var body: some View {
        NavigationStack {
            List {
                if let recognizer {
                    Section { FridgePhotoButton(recognizer: recognizer) }
                }
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
                if !model.data.staples.isEmpty {
                    Section {
                        ForEach(model.data.staples, id: \.self) { Text($0) }
                            .onDelete { offsets in offsets.map { model.data.staples[$0] }.forEach(model.removeStaple) }
                    } header: {
                        Text("Есть дома")
                    } footer: {
                        Text("Специи и масло, отмеченные в рецептах. Смахни влево, если что-то закончилось, — продукт вернётся в список покупок.")
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
            .animation(.smooth, value: model.data.staples)
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
