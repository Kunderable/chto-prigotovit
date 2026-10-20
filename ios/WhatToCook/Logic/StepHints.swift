import Foundation

/// Шаги рецептов — обычный текст, поэтому продукты и время ищем в нём по словам и регуляркой.
enum StepHints {
    /// Продукты «по вкусу» пропускаем: граммовки у них нет.
    static func ingredients(in step: String, from items: [Ingredient]) -> [Ingredient] {
        let stepWords = words(step)
        let stemsByItem = items.map { item in words(item.name).map(stem) }
        let stemCounts = stemsByItem.flatMap { Set($0) }.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }

        return zip(items, stemsByItem).compactMap { item, stems in
            guard item.amount != nil, let first = stems.first else { return nil }
            // остальные слова названия — только уникальные, иначе «масло» совпадёт и со сливочным, и с растительным
            let candidates = [first] + stems.dropFirst().filter { stemCounts[$0] == 1 }
            let mentioned = candidates.contains { candidate in
                candidate.count >= minStemLength && stepWords.contains { $0.hasPrefix(candidate) }
            }
            return mentioned ? item : nil
        }
    }

    /// В секундах. Из «7–8 минут» берём верхнюю границу, «1 час 20 минут» — одна длительность.
    static func durations(in step: String) -> [Int] {
        let text = step.lowercased()
        let pattern = #/(\d+(?:[.,]\d+)?)(?:\s*[–-]\s*(\d+(?:[.,]\d+)?))?\s*(час|ч\b|минут|мин|секунд|сек)\w*\.?(?:\s*(\d+)\s*минут\w*)?/#
        return text.matches(of: pattern).compactMap { match in
            guard let value = number(match.output.2.map(String.init) ?? String(match.output.1)) else { return nil }
            let unit = match.output.3
            let seconds: Double = unit.hasPrefix("ч") ? value * 3600 : unit.hasPrefix("м") ? value * 60 : value
            let extraMinutes = match.output.4.flatMap { Double($0) } ?? 0
            return Int(seconds + extraMinutes * 60)
        }
    }

    private static let minStemLength = 3

    private static func words(_ text: String) -> [String] {
        text.lowercased()
            .replacingOccurrences(of: "ё", with: "е")
            .split { !$0.isLetter }
            .map(String.init)
            .filter { $0.count >= minStemLength }
    }

    /// Отрезаем окончание, чтобы «говядина» нашлась в «говядину», а «масло» — в «маслом».
    private static func stem(_ word: String) -> String {
        switch word.count {
        case 6...: String(word.dropLast(2))
        case 4...5: String(word.dropLast(1))
        default: word
        }
    }

    private static func number(_ text: String) -> Double? {
        Double(text.replacingOccurrences(of: ",", with: "."))
    }
}
