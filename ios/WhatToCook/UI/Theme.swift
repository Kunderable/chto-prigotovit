import SwiftUI
import UIKit

extension Color {
    static let paprika = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.54, blue: 0.30, alpha: 1)
        : UIColor(red: 0.85, green: 0.28, blue: 0.06, alpha: 1) })
    static let protein = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.49, green: 0.48, blue: 1, alpha: 1) : UIColor(red: 0.35, green: 0.34, blue: 0.84, alpha: 1) })
    static let fat = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 1, green: 0.82, blue: 0.25, alpha: 1) : UIColor(red: 0.95, green: 0.66, blue: 0, alpha: 1) })
    static let carbs = Color(uiColor: UIColor { $0.userInterfaceStyle == .dark
        ? UIColor(red: 0.27, green: 0.82, blue: 0.92, alpha: 1) : UIColor(red: 0.11, green: 0.65, blue: 0.77, alpha: 1) })

    static func cuisine(_ cuisine: String, saturation: Double = 0.55, brightness: Double = 0.95) -> Color {
        Color(hue: Catalog.hue(for: cuisine) / 360, saturation: saturation, brightness: brightness)
    }
}

extension View {
    func card(_ radius: CGFloat = 26) -> some View {
        background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

struct DishTile: View {
    let recipe: Recipe
    var size: CGFloat = 44
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let hue = Catalog.hue(for: recipe.cuisine) / 360
        let dark = scheme == .dark
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(LinearGradient(colors: [
                Color(hue: hue, saturation: dark ? 0.45 : 0.22, brightness: dark ? 0.42 : 1),
                Color(hue: hue, saturation: dark ? 0.5 : 0.38, brightness: dark ? 0.3 : 0.92),
            ], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(.white.opacity(dark ? 0.12 : 0.6), lineWidth: 0.5)
            }
            .overlay { Text(recipe.emoji).font(.system(size: size * 0.5)) }
            .frame(width: size, height: size)
            .shadow(color: Color(hue: hue, saturation: 0.6, brightness: 0.4).opacity(0.25), radius: size * 0.12, y: size * 0.06)
            .accessibilityHidden(true)
    }
}

struct AmbientBackground: View {
    var hue: Double
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let dark = scheme == .dark
        let tint = { (shift: Double, alpha: Double) -> Color in
            Color(hue: (hue + shift + 360).truncatingRemainder(dividingBy: 360) / 360,
                  saturation: dark ? 0.6 : 0.45, brightness: dark ? 0.35 : 1).opacity(alpha)
        }
        MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.45], [0.55, 0.4], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: [
            tint(0, 0.55), tint(20, 0.3), tint(40, 0.5),
            tint(-20, 0.18), .clear, tint(30, 0.15),
            .clear, tint(-45, 0.2), .clear,
        ])
        .background(Color(uiColor: .systemGroupedBackground))
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 0.8), value: hue)
    }
}

struct MacroRings: View {
    let eaten: Macros
    let norm: DailyNorm
    var size: CGFloat = 78
    @State private var shown = false

    var body: some View {
        let stroke: CGFloat = 9
        let rings: [(Double, Color)] = [
            (fraction(eaten.protein, norm.protein), .protein), (fraction(eaten.fat, norm.fat), .fat), (fraction(eaten.carbs, norm.carbs), .carbs),
        ]
        ZStack {
            ForEach(Array(rings.enumerated()), id: \.offset) { i, ring in
                let inset = CGFloat(i) * (stroke + 2.5)
                Circle().stroke(ring.1.opacity(0.18), lineWidth: stroke).padding(inset + stroke / 2)
                Circle()
                    .trim(from: 0, to: shown ? ring.0 : 0)
                    .stroke(ring.1, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(inset + stroke / 2)
            }
        }
        .frame(width: size, height: size)
        .onAppear { withAnimation(.smooth(duration: 1.1).delay(0.15)) { shown = true } }
        .animation(.smooth(duration: 0.6), value: eaten)
        .accessibilityElement()
        .accessibilityLabel("Белки \(eaten.protein) из \(norm.protein) г, жиры \(eaten.fat) из \(norm.fat) г, углеводы \(eaten.carbs) из \(norm.carbs) г")
    }

    private func fraction(_ value: Int, _ total: Int) -> Double { total > 0 ? min(1, Double(value) / Double(total)) : 0 }
}

struct StatGrid: View {
    let recipe: Recipe

    var body: some View {
        HStack(spacing: 0) {
            cell("\(recipe.kcal)", "", "ккал", nil)
            cell("\(recipe.protein)", "г", "белки", .protein)
            cell("\(recipe.fat)", "г", "жиры", .fat)
            cell("\(recipe.carbs)", "г", "углеводы", .carbs)
        }
        .padding(.vertical, 14)
        .card(22)
        .accessibilityElement(children: .combine)
    }

    private func cell(_ value: String, _ unit: String, _ label: String, _ color: Color?) -> some View {
        VStack(spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text(value).font(.system(.title2, design: .rounded, weight: .bold)).monospacedDigit()
                Text(unit).font(.footnote).foregroundStyle(.secondary)
            }
            HStack(spacing: 4) {
                if let color { Circle().fill(color).frame(width: 7, height: 7) }
                Text(label).font(.caption).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
    }
}

struct MacroDot: View {
    let color: Color
    var body: some View { Circle().fill(color).frame(width: 7, height: 7) }
}
