//
//  Reminders.swift
//  Cadence
//

import UserNotifications

enum Reminders {
    enum Status: Equatable {
        case ok
        case notDetermined
        case denied
        case failed(String)
    }

    private static var center: UNUserNotificationCenter { .current() }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await center.notificationSettings().authorizationStatus
    }

    static func identifier(for activity: Activity) -> String {
        "activity-\(activity.id.uuidString)"
    }

    /// Replaces all pending reminders with one daily repeating reminder per enabled activity.
    /// Rebuilding from scratch means edited, disabled and deleted activities can't leave stale reminders behind.
    static func sync(_ activities: [Activity], requestingPermission: Bool) async -> Status {
        center.removeAllPendingNotificationRequests()
        let enabled = activities.filter(\.isEnabled)
        guard !enabled.isEmpty else { return .ok }

        var status = await authorizationStatus()
        if status == .notDetermined && requestingPermission {
            do {
                _ = try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                return .failed(error.localizedDescription)
            }
            status = await authorizationStatus()
        }

        switch status {
        case .authorized, .provisional, .ephemeral: break
        case .notDetermined: return .notDetermined
        default: return .denied
        }

        do {
            for activity in enabled {
                let content = UNMutableNotificationContent()
                content.title = activity.name
                content.body = "Time for this activity."
                content.sound = .default
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: activity.hour, minute: activity.minute),
                    repeats: true
                )
                try await center.add(UNNotificationRequest(identifier: identifier(for: activity), content: content, trigger: trigger))
            }
        } catch {
            return .failed(error.localizedDescription)
        }

        // Confirm with the system rather than assuming the adds took.
        let pending = Set(await center.pendingNotificationRequests().map(\.identifier))
        let missing = enabled.filter { !pending.contains(identifier(for: $0)) }
        if !missing.isEmpty {
            return .failed("Missing reminders for: \(missing.map(\.name).joined(separator: ", ")).")
        }
        return .ok
    }
}
