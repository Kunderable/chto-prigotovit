import Foundation

/// Примерная стоимость блюд и покупок. Соль, масло и сухие специи не учитываются.
struct Pricing {
    static let spoonML: [String: Double] = ["ст.л.": 15, "ч.л.": 5]
    /// Если цены известны меньше чем для 70% продуктов, стоимость не показываем.
    static let minCoverage = 0.7
    static let steps = [100, 200, 300]

    let prices: [String: Price]

    /// ₽ за одну единицу `unit` или nil, если цену не пересчитать.
    func unitPrice(_ name: String, unit: String) -> Double? {
        guard let price = prices[name] else { return nil }
        if unit == price.unit { return price.rub }
        if let ml = Self.spoonML[unit], price.unit == "г" || price.unit == "мл" { return price.rub * ml }
        if unit == "шт", price.unit == "г", price.gramsPerPiece > 0 { return price.rub * price.gramsPerPiece }
        return nil
    }

    /// Стоимость продуктов на одну порцию, округлённая до 10 ₽.
    func portionCost(_ recipe: Recipe) -> Int? {
        let paid = recipe.ingredients.filter { !$0.isPantry && $0.amount != nil }
        guard !paid.isEmpty else { return nil }
        var total = 0.0
        var known = 0
        for item in paid {
            guard let price = unitPrice(item.name, unit: item.unit), let amount = item.amount else { continue }
            total += price * amount
            known += 1
        }
        guard Double(known) / Double(paid.count) >= Self.minCoverage else { return nil }
        return max(10, Nutrition.round10(total / Double(max(recipe.servings, 1))))
    }

    /// Сколько придётся потратить в магазине: упаковки покупаются целиком.
    func buyCost(_ rows: [ShoppingRow]) -> Int {
        let total = rows.filter { !$0.have && !$0.isPantry }.reduce(0.0) { sum, row in
            guard let price = unitPrice(row.name, unit: row.unit) else { return sum }
            let amount = row.packs > 0 ? Double(row.packs) * (row.packSize ?? 0) : (row.toBuy > 0 ? row.toBuy : row.amount ?? 0)
            return sum + price * amount
        }
        return Nutrition.round10(total)
    }
}

enum Format {
    /// «вторник, 20 октября» → «Вторник, 20 октября»: заглавная только первая буква.
    nonisolated static func sentence(_ text: String) -> String { text.prefix(1).uppercased() + text.dropFirst() }

    static func rub(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = " "
        return "\(formatter.string(from: NSNumber(value: value)) ?? String(value)) ₽"
    }

    static func amount(_ value: Double?, _ unit: String) -> String {
        guard let value else { return "по вкусу" }
        if unit == "г" || unit == "мл" {
            let rounded = value < 20 ? max(1, Int(value.rounded())) : Int((value / 5).rounded()) * 5
            return "\(rounded) \(unit)"
        }
        let halves = max(0.5, (value * 2).rounded() / 2)
        let whole = Int(halves)
        let text = halves.truncatingRemainder(dividingBy: 1) != 0 ? (whole > 0 ? "\(whole)½" : "½") : "\(whole)"
        return unit.isEmpty ? text : "\(text) \(unit)"
    }

    static func plural(_ count: Int, _ one: String, _ few: String, _ many: String) -> String {
        let lastTwo = abs(count) % 100, last = lastTwo % 10
        if lastTwo > 10 && lastTwo < 20 { return many }
        if last == 1 { return one }
        return (2...4).contains(last) ? few : many
    }
}
