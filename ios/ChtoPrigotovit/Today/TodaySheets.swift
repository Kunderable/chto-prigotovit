import SwiftUI
import UIKit

/// Дневник съеденного: блюда из плана и перекусы, добавленные вручную.
struct DiarySheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kcal = ""
    @State private var p = ""
    @State private var f = ""
    @State private var c = ""
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
                                    Text("\(item.meal.map { $0.title + " · " } ?? "")Б \(item.p) · Ж \(item.f) · У \(item.c)")
                                        .font(.footnote).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(item.kcal) ккал").foregroundStyle(.secondary).monospacedDigit()
                            }
                        }
                        .onDelete { offsets in offsets.map { items[$0] }.forEach(model.removeDiary) }
                    } footer: {
                        let total = model.eatenToday
                        Text("Всего \(total.kcal) ккал · Б \(total.p) · Ж \(total.f) · У \(total.c)")
                    }
                }
                Section("Добавить перекус") {
                    TextField("Яблоко, кофе с молоком…", text: $name)
                    HStack {
                        field("ккал", $kcal)
                        field("Б", $p)
                        field("Ж", $f)
                        field("У", $c)
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
        let numbers = [kcal, p, f, c].map { Double($0.replacingOccurrences(of: ",", with: ".")) ?? 0 }
        guard numbers.allSatisfy({ $0 >= 0 && $0 <= 5000 }) else { error = "КБЖУ — числа от 0 до 5000."; return }
        let total = numbers[0] > 0 ? numbers[0] : numbers[1] * 4 + numbers[2] * 9 + numbers[3] * 4
        guard total > 0 else { error = "Укажи калории или БЖУ."; return }
        model.addDiary(DiaryEntry(id: "custom-\(UUID().uuidString)", name: String(trimmed.prefix(60)), kcal: Int(total.rounded()),
                                  p: Int(numbers[1].rounded()), f: Int(numbers[2].rounded()), c: Int(numbers[3].rounded())))
        name = ""; kcal = ""; p = ""; f = ""; c = ""; error = nil
    }
}

/// Покупки на весь день: одинаковые продукты из разных блюд сложены.
struct ShoppingSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let rows = model.dayShoppingRows
        let text = Shopping.listText(title: "Покупки на \(Date.now.formatted(.dateTime.day().month(.wide)))", rows: rows)
        NavigationStack {
            List {
                if rows.isEmpty {
                    ContentUnavailableView("Всё есть дома", systemImage: "checkmark.circle")
                } else {
                    Section {
                        ForEach(rows) { row in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(row.name)
                                    if row.packs > 0 {
                                        Text("\(row.packs) уп. по \(Format.amount(row.pack, row.unit))").font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(Format.amount(row.toBuy > 0 ? row.toBuy : row.amount, row.unit)).foregroundStyle(.secondary)
                            }
                        }
                    } footer: {
                        let cost = model.pricing.buyCost(rows)
                        if cost > 0 { Text("Примерно \(Format.rub(cost)) с учётом целых упаковок") }
                    }
                }
            }
            .navigationTitle("Покупки на сегодня")
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
