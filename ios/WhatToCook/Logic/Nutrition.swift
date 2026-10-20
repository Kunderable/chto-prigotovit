import Foundation

struct DailyNorm: Equatable {
    let kcal: Int
    let protein: Int
    let fat: Int
    let carbs: Int
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
        let protein = Int((body.weight * proteinPerKg(goal)).rounded())
        func fatFilling(carbs: Int) -> Int { Int((Double(kcal - protein * 4 - carbs * 4) / 9).rounded()) }
        var carbs: Int
        var fat: Int
        if goal == .lowcarb {
            carbs = lowcarbDayCarbs
            fat = fatFilling(carbs: carbs)
        } else {
            fat = Int((body.weight * fatPerKg).rounded())
            carbs = Int((Double(kcal - protein * 4 - fat * 9) / 4).rounded())
            if carbs < minDayCarbs {
                carbs = minDayCarbs
                fat = fatFilling(carbs: carbs)
            }
        }
        return DailyNorm(kcal: kcal, protein: protein, fat: fat, carbs: carbs, bmr: Int(bmr.rounded()), tdee: round10(tdee))
    }

    enum BodyInputError: Error, Equatable {
        case missing(String)
        case outOfRange(String, Int, Int)

        var message: String {
            switch self {
            case .missing(let field): "Заполни \(field) — без него не посчитать норму."
            case .outOfRange(let field, let min, let max): "\(Format.sentence(field)) должен быть от \(min) до \(max)."
            }
        }
    }

    static func parseBody(sex: Sex, age: String, height: String, weight: String, activity: Double) throws(BodyInputError) -> BodyData {
        func number(_ text: String, _ field: String, _ min: Int, _ max: Int) throws(BodyInputError) -> Double {
            let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
            guard !trimmed.isEmpty, let value = Double(trimmed) else { throw .missing(field) }
            guard value >= Double(min), value <= Double(max) else { throw .outOfRange(field, min, max) }
            return value
        }
        let ageValue = try number(age, "возраст", 14, 100)
        let heightValue = try number(height, "рост", 120, 230)
        let weightValue = try number(weight, "вес", 35, 250)
        return BodyData(sex: sex, age: Int(ageValue), height: heightValue, weight: weightValue, activity: activity)
    }

    static func round10(_ value: Double) -> Int { Int((value / 10).rounded()) * 10 }
}
