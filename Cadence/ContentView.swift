//
//  ContentView.swift
//  Cadence
//
//  Created by Max on 12/10/26.
//

import Combine
import SwiftUI

struct ContentView: View {
    @State private var store = ActivityStore()
    @State private var editing: Activity?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            List {
                if store.reminderStatus != .ok {
                    reminderBanner
                }
                Section {
                    ForEach(store.enabled) { row($0) }
                }
                if !store.paused.isEmpty {
                    Section("Paused") {
                        ForEach(store.paused) { row($0) }
                    }
                }
            }
            .overlay {
                if store.activities.isEmpty {
                    ContentUnavailableView("No Activities", systemImage: "clock", description: Text("Add an activity to get a daily reminder."))
                }
            }
            .animation(.default, value: store.activities)
            .navigationTitle("Today")
            .navigationSubtitle(store.today.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            .safeAreaInset(edge: .bottom) {
                Button {
                    let nextHour = (Calendar.current.component(.hour, from: .now) + 1) % 24
                    editing = Activity(name: "", hour: nextHour, minute: 0)
                } label: {
                    Label("New Activity", systemImage: "plus")
                        .font(.headline)
                        .padding(.horizontal, 8)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .padding(.bottom, 8)
            }
            .sheet(item: $editing) { activity in
                ActivityEditor(
                    activity: activity,
                    isNew: !store.contains(activity),
                    onSave: { store.save($0) },
                    onDelete: { store.delete(activity) }
                )
            }
            .alert("Something Went Wrong", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(store.errorMessage ?? "")
            }
        }
        .fontDesign(.rounded)
        .onChange(of: scenePhase, initial: true) { _, phase in
            guard phase == .active else { return }
            store.refreshDay()
            store.syncReminders()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            store.refreshDay()
        }
    }

    private func row(_ activity: Activity) -> some View {
        let done = activity.isEnabled && activity.isDone(on: store.today)
        return HStack(spacing: 14) {
            if activity.isEnabled {
                Button {
                    store.toggleDone(activity)
                } label: {
                    Image(systemName: done ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundStyle(done ? Color.accentColor : .secondary)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(done ? "Mark \(activity.name) not done" : "Mark \(activity.name) done")
            }

            Button {
                editing = activity
            } label: {
                HStack {
                    Text(activity.name)
                        .strikethrough(done, color: .secondary)
                        .foregroundStyle(done || !activity.isEnabled ? .secondary : .primary)
                    Spacer()
                    Text(activity.time, format: .dateTime.hour().minute())
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .swipeActions(edge: .trailing) {
            Button("Delete", systemImage: "trash", role: .destructive) {
                store.delete(activity)
            }
        }
        .swipeActions(edge: .leading) {
            Button(activity.isEnabled ? "Pause" : "Resume", systemImage: activity.isEnabled ? "pause" : "play") {
                store.setEnabled(!activity.isEnabled, for: activity)
            }
            .tint(activity.isEnabled ? .orange : .green)
        }
    }

    @ViewBuilder
    private var reminderBanner: some View {
        Section {
            switch store.reminderStatus {
            case .denied:
                Label("Notifications are off for Cadence. Turn them on in Settings › Notifications › Cadence to get reminders.", systemImage: "bell.slash")
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) }
                }
            case .notDetermined:
                Label("Reminders aren't set up yet.", systemImage: "bell")
                Button("Allow Notifications") { store.syncReminders(requestingPermission: true) }
            case .failed(let message):
                Label("Reminders couldn't be scheduled. \(message)", systemImage: "exclamationmark.triangle")
                Button("Try Again") { store.syncReminders() }
            case .ok:
                EmptyView()
            }
        }
        .font(.subheadline)
    }
}

#Preview {
    ContentView()
}
