import Foundation

struct ShoppingRow: Identifiable, Equatable {
    var id: String { "\(name)|\(unit)" }
    let name: String
    let unit: String
    let amount: Double?
    let packSize: Double?
    var fromFridge: Double
    var toBuy: Double
    var have: Bool
    var packs: Int
    var leftover: Double
    var inFridge: Bool
    /// Специи и масло: их покупают редко, и «есть дома» запоминается для всех блюд сразу.
    var isPantry = false
}

/// Граммовка под порции, список покупок с учётом холодильника, остатки после готовки.
enum Shopping {
    static let leftoverMin: [String: Double] = ["г": 10, "мл": 10, "шт": 1, "зубч.": 1]

    static func scaled(_ recipe: Recipe, portions: Int) -> [Ingredient] {
        let scale = Double(portions) / Double(max(recipe.servings, 1))
        return recipe.ingredients.map { Ingredient(name: $0.name, amount: $0.amount.map { $0 * scale }, unit: $0.unit, packSize: $0.packSize, isPantry: $0.isPantry) }
    }

    static func fridgeMatch(_ fridge: [FridgeItem], _ item: Ingredient) -> FridgeItem? {
        fridge.first { same($0.name, item.name) && ($0.amount == nil || $0.unit == item.unit) }
    }

    static func rows(_ recipe: Recipe, plan: PlannedMeal, fridge: [FridgeItem], staples: [String] = []) -> [ShoppingRow] {
        let items = scaled(recipe, portions: plan.portions)
        let pantry = items.filter(\.isPantry).map { item in
            ShoppingRow(name: item.name, unit: item.unit, amount: item.amount, packSize: nil, fromFridge: 0, toBuy: 0,
                        have: staples.contains { same($0, item.name) }, packs: 0, leftover: 0, inFridge: false, isPantry: true)
        }
        return items.filter { !$0.isPantry }.map { item in
            let match = fridgeMatch(fridge, item)
            let need = item.amount ?? 0
            let fromFridge = match.map { $0.amount == nil ? need : min($0.amount!, need) } ?? 0
            let toBuy = item.amount == nil ? 0 : max(0, need - fromFridge)
            let have = plan.have.contains(item.name) || (match != nil && toBuy == 0)
            let packs = (item.packSize ?? 0) > 0 && toBuy > 0 ? Int((toBuy / item.packSize!).rounded(.up)) : 0
            let leftover = packs > 0 ? Double(packs) * item.packSize! - toBuy : 0
            return ShoppingRow(name: item.name, unit: item.unit, amount: item.amount, packSize: item.packSize, fromFridge: fromFridge,
                               toBuy: toBuy, have: have, packs: packs, leftover: leftover, inFridge: match != nil)
        } + pantry
    }

    /// Одинаковые продукты из разных блюд складываются.
    static func merge(_ lists: [[ShoppingRow]]) -> [ShoppingRow] {
        var merged: [String: ShoppingRow] = [:]
        var order: [String] = []
        for row in lists.joined() where !row.have {
            let key = (row.isPantry ? row.name : row.id).lowercased()
            let add = row.toBuy > 0 ? row.toBuy : row.amount ?? 0
            if var existing = merged[key] {
                existing.toBuy += add
                existing.packs = (existing.packSize ?? 0) > 0 ? Int((existing.toBuy / existing.packSize!).rounded(.up)) : 0
                merged[key] = existing
            } else {
                var copy = row
                copy.toBuy = add
                copy.packs = (row.packSize ?? 0) > 0 ? Int((add / row.packSize!).rounded(.up)) : 0
                merged[key] = copy
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }
    }

    static func listText(title: String, rows: [ShoppingRow]) -> String {
        let lines = rows.filter { !$0.have }.map { row in
            if row.isPantry { return "• \(row.name)" }
            let amount = Format.amount(row.toBuy > 0 ? row.toBuy : row.amount, row.unit)
            let packs = row.packs > 0 ? " (\(row.packs) уп. по \(Format.amount(row.packSize, row.unit)))" : ""
            return "• \(row.name) — \(amount)\(packs)"
        }
        return "\(title):\n" + (lines.isEmpty ? "всё уже есть дома" : lines.joined(separator: "\n"))
    }

    /// Что окажется в холодильнике после готовки: тратим запасы, остаток упаковок добавляем.
    static func fridgeAfterCooking(_ recipe: Recipe, plan: PlannedMeal, fridge: [FridgeItem]) -> (fridge: [FridgeItem], added: [String]) {
        var result = fridge
        var added: [String] = []
        for item in scaled(recipe, portions: plan.portions) where !item.isPantry {
            var need = item.amount ?? 0
            if let index = result.firstIndex(where: { same($0.name, item.name) && ($0.amount == nil || $0.unit == item.unit) }) {
                if let amount = result[index].amount {
                    let take = min(amount, need)
                    need -= take
                    result[index].amount = amount - take
                } else {
                    result.remove(at: index)
                    need = 0
                }
            }
            if plan.have.contains(item.name) { need = 0 }
            if need > 0, let pack = item.packSize, pack > 0 {
                let left = (need / pack).rounded(.up) * pack - need
                if left >= (leftoverMin[item.unit] ?? 1) {
                    result.append(FridgeItem(name: item.name, amount: left, unit: item.unit))
                    added.append("\(item.name.lowercased()) \(Format.amount(left, item.unit))")
                }
            }
        }
        result.removeAll { item in
            guard let amount = item.amount else { return false }
            return amount < (leftoverMin[item.unit] ?? 1) * 0.5
        }
        return (result, added)
    }

    static func same(_ first: String, _ second: String) -> Bool {
        first.trimmingCharacters(in: .whitespaces).lowercased() == second.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
