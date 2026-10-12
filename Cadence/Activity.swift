//
//  Activity.swift
//  Cadence
//

import Foundation
import Observation

struct Activity: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var hour: Int
    var minute: Int
    var isEnabled = true
    /// Local calendar day ("yyyy-MM-dd") the activity was last checked off.
    var completedDay: String?

    var time: Date {
        Calendar.current.date(bySettingHour: hour, minute: minute, second: 0, of: .now) ?? .now
    }

    func isDone(on day: Date) -> Bool {
        completedDay == Activity.dayKey(day)
    }

    static func dayKey(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }
}

/// Owns the activity list, its JSON file, and keeping reminders in step with it.
@Observable
final class ActivityStore {
    private(set) var activities: [Activity] = []
    /// Start of the current local day. Completion is derived from this, so nothing needs resetting at midnight.
    private(set) var today = Calendar.current.startOfDay(for: .now)
    private(set) var reminderStatus: Reminders.Status = .ok
    var errorMessage: String?

    private let fileURL = URL.applicationSupportDirectory.appending(path: "activities.json")
    private var syncTask: Task<Void, Never>?

    init() {
        load()
    }

    var enabled: [Activity] { sorted(activities.filter(\.isEnabled)) }
    var paused: [Activity] { sorted(activities.filter { !$0.isEnabled }) }

    func contains(_ activity: Activity) -> Bool {
        activities.contains { $0.id == activity.id }
    }

    func refreshDay() {
        let start = Calendar.current.startOfDay(for: .now)
        if start != today { today = start }
    }

    func toggleDone(_ activity: Activity) {
        guard let i = activities.firstIndex(where: { $0.id == activity.id }) else { return }
        refreshDay()
        activities[i].completedDay = activities[i].isDone(on: today) ? nil : Activity.dayKey(today)
        persist()
    }

    func save(_ activity: Activity) {
        if let i = activities.firstIndex(where: { $0.id == activity.id }) {
            activities[i] = activity
        } else {
            activities.append(activity)
        }
        persist()
        syncReminders(requestingPermission: activity.isEnabled)
    }

    func setEnabled(_ isEnabled: Bool, for activity: Activity) {
        guard var current = activities.first(where: { $0.id == activity.id }) else { return }
        current.isEnabled = isEnabled
        save(current)
    }

    func delete(_ activity: Activity) {
        activities.removeAll { $0.id == activity.id }
        persist()
        syncReminders()
    }

    /// Syncs run one after another so an older snapshot can never re-add a removed reminder.
    func syncReminders(requestingPermission: Bool = false) {
        let previous = syncTask
        syncTask = Task {
            await previous?.value
            reminderStatus = await Reminders.sync(activities, requestingPermission: requestingPermission)
        }
    }

    private func sorted(_ list: [Activity]) -> [Activity] {
        list.sorted {
            ($0.hour, $0.minute, $0.name.localizedLowercase) < ($1.hour, $1.minute, $1.name.localizedLowercase)
        }
    }

    private func persist() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(activities).write(to: fileURL, options: .atomic)
        } catch {
            errorMessage = "Couldn't save your activities. \(error.localizedDescription)"
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        do {
            activities = try JSONDecoder().decode([Activity].self, from: Data(contentsOf: fileURL))
        } catch {
            // Move the unreadable file aside so the next save doesn't overwrite it.
            let backup = fileURL.deletingPathExtension().appendingPathExtension("unreadable.json")
            try? FileManager.default.removeItem(at: backup)
            try? FileManager.default.moveItem(at: fileURL, to: backup)
            errorMessage = "Your saved activities couldn't be read. The file was kept as \(backup.lastPathComponent)."
        }
    }
}
