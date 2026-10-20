import SwiftUI
import UIKit

/// Дневник съеденного: блюда из плана и перекусы, добавленные вручную.
struct DiarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcalText = ""
    @State private var proteinText = ""
    @State private var fatText = ""
    @State private var carbsText = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                let items = model.diaryToday
                if items.isEmpty {
                    ContentUnavailableView("Пока пусто", systemImage: "fork.knife",
                                           description: Text("Отметь блюдо из плана или добавь перекус ниже."))
                } else {
                    Section {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.name)
                                    Text("\(item.meal.map { $0.title + " · " } ?? "")Б \(item.protein) · Ж \(item.fat) · У \(item.carbs)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.kcal) ккал").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .onDelete { offsets in offsets.map { items[$0] }.forEach(model.removeDiary) }
                    } footer: {
                        let total = model.eatenToday
                        Text("Всего \(total.kcal) ккал · Б \(total.protein) · Ж \(total.fat) · У \(total.carbs)")
                    }
                }
                Section("Добавить перекус") {
                    TextField("Яблоко, кофе с молоком…", text: $name)
                    HStack {
                        field("ккал", $kcalText)
                        field("Б", $proteinText)
                        field("Ж", $fatText)
                        field("У", $carbsText)
                    }
                    Button("Добавить", action: add)
                    if let error { Text(error).foregroundStyle(.red).font(.footnote) }
                }
            }
            .navigationTitle("Дневник")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Готово") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }

    private func field(_ title: String, _ text: Binding<String>) -> some View {
        TextField(title, text: text).keyboardType(.decimalPad).multilineTextAlignment(.center)
    }

    private func add() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { error = "Напиши, что съел."; return }
        func number(_ text: String) -> Double { Double(text.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        let kcal = number(kcalText), protein = number(proteinText), fat = number(fatText), carbs = number(carbsText)
        guard [kcal, protein, fat, carbs].allSatisfy({ $0 >= 0 && $0 <= 5000 }) else { error = "КБЖУ — числа от 0 до 5000."; return }
        // если калории не указаны, считаем их из БЖУ: 4 ккал на грамм белков и углеводов, 9 — на грамм жиров
        let totalKcal = kcal > 0 ? kcal : protein * 4 + fat * 9 + carbs * 4
        guard totalKcal > 0 else { error = "Укажи калории или БЖУ."; return }
        model.addDiary(DiaryEntry(id: "custom-\(UUID().uuidString)", name: String(trimmed.prefix(60)), kcal: Int(totalKcal.rounded()),
                                  protein: Int(protein.rounded()), fat: Int(fat.rounded()), carbs: Int(carbs.rounded())))
        name = ""; kcalText = ""; proteinText = ""; fatText = ""; carbsText = ""; error = nil
    }
}

/// Что купить на сегодня: продукты блюд, которые ещё не съедены и не приготовлены; одинаковые сложены.
struct ShoppingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let rows = model.dayShoppingRows
        let text = Shopping.listText(title: "Купить на \(Date.now.formatted(.dateTime.day().month(.wide)))", rows: rows)
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("Всё есть дома", systemImage: "checkmark.circle")
                } else {
                    Section {
                        ForEach(rows.filter { !$0.isPantry }) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    if row.packs > 0 {
                                        Text("\(row.packs) уп. по \(Format.amount(row.packSize, row.unit))").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Format.amount(row.toBuy > 0 ? row.toBuy : row.amount, row.unit)).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        let cost = model.pricing.buyCost(rows)
                        Text((cost > 0 ? "Примерно \(Format.rub(cost)) с учётом целых упаковок. " : "")
                             + "Если что-то уже есть дома, отметь это в рецепте — продукт пропадёт из списка.")
                    }
                    let pantry = rows.filter(\.isPantry)
                    if !pantry.isEmpty {
                        Section("Специи и масло, если закончились") {
                            ForEach(pantry) { Text($0.name) }
                        }
                    }
                }
            }
            .navigationTitle("Купить на сегодня")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Готово") { dismiss() } }
                if !rows.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: text) { Image(systemName: "square.and.arrow.up") }
                    }
                    ToolbarItem(placement: .bottomBar) {
                        Button {
                            UIPasteboard.general.string = text
                            copied = true
                        } label: {
                            Label(copied ? "Скопировано" : "Скопировать список", systemImage: copied ? "checkmark" : "doc.on.doc")
                                .contentTransition(.symbolEffect(.replace))
                        }
                        .buttonStyle(.glassProminent)
                        .sensoryFeedback(.success, trigger: copied)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
