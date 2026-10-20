import Foundation

struct ShoppingRow: Identifiable, Equatable {
    var id: String { "\(name)|\(unit)" }
    let name: String
    let unit: String
    let amount: Double?
    let pack: Double?
    var fromFridge: Double
    var toBuy: Double
    var have: Bool
    var packs: Int
    var leftover: Double
    var inFridge: Bool
}

/// Граммовка под порции, список покупок с учётом холодильника, остатки после готовки.
enum Shopping {
    static let leftoverMin: [String: Double] = ["г": 10, "мл": 10, "шт": 1, "зубч.": 1]

    static func scaled(_ recipe: Recipe, portions: Int) -> [Ingredient] {
        let k = Double(portions) / Double(max(recipe.base, 1))
        return recipe.ingredients.map { Ingredient(n: $0.n, a: $0.a.map { $0 * k }, u: $0.u, pack: $0.pack, pantry: $0.pantry) }
    }

    static func fridgeMatch(_ fridge: [FridgeItem], _ item: Ingredient) -> FridgeItem? {
        fridge.first { same($0.name, item.n) && ($0.amount == nil || $0.unit == item.u) }
    }

    static func rows(_ recipe: Recipe, plan: PlannedMeal, fridge: [FridgeItem]) -> [ShoppingRow] {
        scaled(recipe, portions: plan.portions).filter { !$0.isPantry }.map { item in
            let match = fridgeMatch(fridge, item)
            let need = item.a ?? 0
            let fromFridge = match.map { $0.amount == nil ? need : min($0.amount!, need) } ?? 0
            let toBuy = item.a == nil ? 0 : max(0, need - fromFridge)
            let have = plan.have.contains(item.n) || (match != nil && toBuy == 0)
            let packs = (item.pack ?? 0) > 0 && toBuy > 0 ? Int((toBuy / item.pack!).rounded(.up)) : 0
            let leftover = packs > 0 ? Double(packs) * item.pack! - toBuy : 0
            return ShoppingRow(name: item.n, unit: item.u, amount: item.a, pack: item.pack, fromFridge: fromFridge,
                               toBuy: toBuy, have: have, packs: packs, leftover: leftover, inFridge: match != nil)
        }
    }

    /// Одинаковые продукты из разных блюд складываются.
    static func merge(_ lists: [[ShoppingRow]]) -> [ShoppingRow] {
        var merged: [String: ShoppingRow] = [:]
        var order: [String] = []
        for row in lists.joined() where !row.have {
            let key = row.id.lowercased()
            let add = row.toBuy > 0 ? row.toBuy : row.amount ?? 0
            if var existing = merged[key] {
                existing.toBuy += add
                existing.packs = (existing.pack ?? 0) > 0 ? Int((existing.toBuy / existing.pack!).rounded(.up)) : 0
                merged[key] = existing
            } else {
                var copy = row
                copy.toBuy = add
                copy.packs = (row.pack ?? 0) > 0 ? Int((add / row.pack!).rounded(.up)) : 0
                merged[key] = copy
                order.append(key)
            }
        }
        return order.compactMap { merged[$0] }
    }

    static func listText(title: String, rows: [ShoppingRow]) -> String {
        let lines = rows.filter { !$0.have }.map { row in
            let amount = Format.amount(row.toBuy > 0 ? row.toBuy : row.amount, row.unit)
            let packs = row.packs > 0 ? " (\(row.packs) уп. по \(Format.amount(row.pack, row.unit)))" : ""
            return "• \(row.name) — \(amount)\(packs)"
        }
        return "\(title):\n" + (lines.isEmpty ? "всё уже есть дома" : lines.joined(separator: "\n"))
    }

    /// Что окажется в холодильнике после готовки: тратим запасы, остаток упаковок добавляем.
    static func fridgeAfterCooking(_ recipe: Recipe, plan: PlannedMeal, fridge: [FridgeItem]) -> (fridge: [FridgeItem], added: [String]) {
        var result = fridge
        var added: [String] = []
        for item in scaled(recipe, portions: plan.portions) where !item.isPantry {
            var need = item.a ?? 0
            if let index = result.firstIndex(where: { same($0.name, item.n) && ($0.amount == nil || $0.unit == item.u) }) {
                if let amount = result[index].amount {
                    let take = min(amount, need)
                    need -= take
                    result[index].amount = amount - take
                } else {
                    result.remove(at: index)
                    need = 0
                }
            }
            if plan.have.contains(item.n) { need = 0 }
            if need > 0, let pack = item.pack, pack > 0 {
                let left = (need / pack).rounded(.up) * pack - need
                if left >= (leftoverMin[item.u] ?? 1) {
                    result.append(FridgeItem(name: item.n, amount: left, unit: item.u))
                    added.append("\(item.n.lowercased()) \(Format.amount(left, item.u))")
                }
            }
        }
        result.removeAll { item in
            guard let amount = item.amount else { return false }
            return amount < (leftoverMin[item.unit] ?? 1) * 0.5
        }
        return (result, added)
    }

    static func same(_ a: String, _ b: String) -> Bool {
        a.trimmingCharacters(in: .whitespaces).lowercased() == b.trimmingCharacters(in: .whitespaces).lowercased()
    }
}
