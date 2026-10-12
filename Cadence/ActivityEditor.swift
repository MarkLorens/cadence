//
//  ActivityEditor.swift
//  Cadence
//

import SwiftUI

struct ActivityEditor: View {
    let isNew: Bool
    let onSave: (Activity) -> Void
    let onDelete: () -> Void

    @State private var activity: Activity
    @State private var time: Date
    @State private var permissionNotAsked = false
    @Environment(\.dismiss) private var dismiss

    init(activity: Activity, isNew: Bool, onSave: @escaping (Activity) -> Void, onDelete: @escaping () -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _activity = State(initialValue: activity)
        _time = State(initialValue: activity.time)
    }

    private var trimmedName: String {
        activity.name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $activity.name)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Toggle("Enabled", isOn: $activity.isEnabled)
                } footer: {
                    if permissionNotAsked && activity.isEnabled {
                        Text("Cadence will ask permission to send you a reminder at this time each day.")
                    }
                }

                if !isNew {
                    Section {
                        Button("Delete Activity", role: .destructive) {
                            onDelete()
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(isNew ? "New Activity" : "Edit Activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .task {
                permissionNotAsked = await Reminders.authorizationStatus() == .notDetermined
            }
        }
    }

    private func save() {
        let components = Calendar.current.dateComponents([.hour, .minute], from: time)
        var saved = activity
        saved.name = trimmedName
        saved.hour = components.hour ?? 0
        saved.minute = components.minute ?? 0
        onSave(saved)
        dismiss()
    }
}
