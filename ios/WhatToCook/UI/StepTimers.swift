import Foundation
import Observation
import UserNotifications
import os

/// Хранится в App, а не в экране блюда: таймер не должен сбрасываться при уходе с экрана.
@Observable
final class StepTimers: NSObject, UNUserNotificationCenterDelegate {
    private(set) var endDates: [String: Date] = [:]
    private let center = UNUserNotificationCenter.current()
    private static let log = Logger(subsystem: "ru.chtoprigotovit.app", category: "timers")

    override init() {
        super.init()
        center.delegate = self
    }

    func endDate(_ id: String) -> Date? {
        guard let end = endDates[id], end > .now else { return nil }
        return end
    }

    func start(id: String, seconds: Int, title: String, body: String) {
        endDates[id] = .now.addingTimeInterval(TimeInterval(seconds))
        Task {
            do {
                guard try await center.requestAuthorization(options: [.alert, .sound]) else { return }
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(seconds), repeats: false)
                try await center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
            } catch {
                Self.log.error("Не удалось запланировать уведомление: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func stop(id: String) {
        endDates[id] = nil
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
