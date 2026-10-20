import Foundation

struct DailyNorm: Equatable {
    let kcal: Int
    let p: Int
    let f: Int
    let c: Int
    let bmr: Int
    let tdee: Int
}

/// Норма КБЖУ по формуле Миффлина — Сан-Жеора с поправкой на активность и цель.
enum Nutrition {
    static let activity: [(value: Double, title: String)] = [
        (1.2, "Почти не двигаюсь"),
        (1.375, "Тренировки 1–3 раза в неделю"),
        (1.55, "Тренировки 3–5 раз в неделю"),
        (1.725, "Тренируюсь почти каждый день"),
    ]
    static let lowcarbDayCarbs = 80
    static let minDayCarbs = 50
    static let fatPerKg = 0.9

    static func goalFactor(_ goal: Goal) -> Double {
        switch goal {
        case .lose: 0.83
        case .lowcarb: 0.9
        case .normal, .protein: 1
        }
    }

    static func proteinPerKg(_ goal: Goal) -> Double {
        switch goal {
        case .normal: 1.2
        case .lose, .lowcarb: 1.6
        case .protein: 2
        }
    }

    static func norm(body: BodyData, goal: Goal) -> DailyNorm {
        let bmr = 10 * body.weight + 6.25 * body.height - 5 * Double(body.age) + (body.sex == .male ? 5 : -161)
        let tdee = bmr * body.activity
        let floor = body.sex == .male ? 1500 : 1200
        let kcal = max(floor, round10(tdee * goalFactor(goal)))
        let p = Int((body.weight * proteinPerKg(goal)).rounded())
        var c: Int
        var f: Int
        if goal == .lowcarb {
            c = lowcarbDayCarbs
            f = Int((Double(kcal - p * 4 - c * 4) / 9).rounded())
        } else {
            f = Int((body.weight * fatPerKg).rounded())
            c = Int((Double(kcal - p * 4 - f * 9) / 4).rounded())
            if c < minDayCarbs {
                c = minDayCarbs
                f = Int((Double(kcal - p * 4 - c * 4) / 9).rounded())
            }
        }
        return DailyNorm(kcal: kcal, p: p, f: f, c: c, bmr: Int(bmr.rounded()), tdee: round10(tdee))
    }

    enum BodyInputError: Error, Equatable {
        case missing(String)
        case outOfRange(String, Int, Int)

        var message: String {
            switch self {
            case .missing(let field): "Укажи: \(field)."
            case .outOfRange(let field, let lo, let hi): "\(field.capitalized) — от \(lo) до \(hi)."
            }
        }
    }

    /// Разбирает текст из полей ввода; запятая в дробях допустима.
    static func parseBody(sex: Sex, age: String, height: String, weight: String, activity: Double) throws(BodyInputError) -> BodyData {
        func number(_ text: String, _ field: String, _ lo: Int, _ hi: Int) throws(BodyInputError) -> Double {
            let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard !trimmed.isEmpty, let value = Double(trimmed) else { throw .missing(field) }
            guard value >= Double(lo), value <= Double(hi) else { throw .outOfRange(field, lo, hi) }
            return value
        }
        let a = try number(age, "возраст", 14, 100)
        let h = try number(height, "рост", 120, 230)
        let w = try number(weight, "вес", 35, 250)
        return BodyData(sex: sex, age: Int(a), height: h, weight: w, activity: activity)
    }

    static func round10(_ x: Double) -> Int { Int((x / 10).rounded()) * 10 }
}
