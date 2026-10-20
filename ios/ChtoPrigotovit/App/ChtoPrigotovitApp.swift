import SwiftUI

@main
struct ChtoPrigotovitApp: App {
    @State private var model = AppModel.live()
    @State private var router = Router()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .environment(router)
                .tint(.paprika)
        }
    }
}

enum AppTab: Hashable { case today, catalog, fridge, profile }

/// Переходы между вкладками, например «поставить рецепт из каталога в план и открыть его».
@Observable
final class Router {
    var tab: AppTab = .today
    var todayPath: [MealKind] = []

    func openPlanned(_ kind: MealKind) {
        tab = .today
        todayPath = [kind]
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(Router.self) private var router

    var body: some View {
        @Bindable var router = router
        Group {
            if model.data.onboarded {
                TabView(selection: $router.tab) {
                    Tab("Сегодня", systemImage: "fork.knife", value: AppTab.today) { TodayView() }
                    Tab("Рецепты", systemImage: "book.pages", value: AppTab.catalog) { CatalogView() }
                    Tab("Холодильник", systemImage: "refrigerator", value: AppTab.fridge) { FridgeView() }
                        .badge(model.data.fridge.count)
                    Tab("Профиль", systemImage: "person.crop.circle", value: AppTab.profile) { ProfileView() }
                }
                .tabBarMinimizeBehavior(.onScrollDown)
                .transition(.opacity)
            } else {
                OnboardingView()
                    .transition(.opacity)
            }
        }
        .animation(.smooth, value: model.data.onboarded)
    }
}
