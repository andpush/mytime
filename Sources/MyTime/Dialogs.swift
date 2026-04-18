import SwiftUI
import AppKit

// MARK: - Start Timer Dialog

struct StartTimerView: View {
    let clients: [String]
    let activities: [String]
    var onStart: (String, String) -> Void
    var onCancel: () -> Void

    @State private var client: String = ""
    @State private var activity: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Start New Timer").font(.headline)

            AutocompleteField(title: "Client", text: $client, suggestions: clients)
            AutocompleteField(title: "Activity (optional)", text: $activity, suggestions: activities)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Start") {
                    let c = client.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !c.isEmpty else { return }
                    onStart(c, activity.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                .keyboardShortcut(.defaultAction)
                .disabled(client.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

struct AutocompleteField: View {
    let title: String
    @Binding var text: String
    let suggestions: [String]

    var filtered: [String] {
        let t = text.lowercased()
        if t.isEmpty { return Array(suggestions.prefix(5)) }
        return suggestions.filter { $0.lowercased().contains(t) && $0.lowercased() != t }.prefix(5).map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundColor(.secondary)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
            if !filtered.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(filtered, id: \.self) { s in
                            Button(action: { text = s }) {
                                Text(s).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 2).padding(.horizontal, 6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .frame(maxHeight: 80)
                .background(Color(nsColor: .controlBackgroundColor))
                .cornerRadius(4)
            }
        }
    }
}

// MARK: - Settings Dialog

struct SettingsView: View {
    @State var config: AppConfig
    var onSave: (AppConfig) -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings").font(.headline)

            GroupBox(label: Text("Pomodoro")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Enable Pomodoro mode", isOn: $config.pomodoroEnabled)
                    HStack {
                        Text("Work interval (minutes)")
                        Stepper(value: $config.pomodoroWorkMinutes, in: 1...180) {
                            Text("\(config.pomodoroWorkMinutes)")
                        }
                    }.disabled(!config.pomodoroEnabled)
                    Text("When enabled, the active timer auto-stops after this many minutes and a notification tells you the work interval is over.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }

            GroupBox(label: Text("Reminders & Auto-pause")) {
                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Remind to track (minutes)")
                            Stepper(value: $config.remindTrackingMinutes, in: 1...600) {
                                Text("\(config.remindTrackingMinutes)")
                            }
                        }
                        Text("If no timer has been active for this long, show a notification reminding you to start tracking.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Idle to auto-pause (minutes)")
                            Stepper(value: $config.idleToPauseMinutes, in: 1...600) {
                                Text("\(config.idleToPauseMinutes)")
                            }
                        }
                        Text("If you stop using the computer for this long, the active timer is paused automatically (also on sleep / closing the lid).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }.padding(8)
            }

            GroupBox(label: Text("Startup")) {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("Launch MyTime at login", isOn: $config.launchAtLogin)
                    Text("Installs a per-user LaunchAgent so MyTime starts automatically when you log in.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }

            GroupBox(label: Text("Crash recovery")) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Heartbeat every (minutes)")
                        Stepper(value: $config.heartbeatMinutes, in: 1...60) {
                            Text("\(config.heartbeatMinutes)")
                        }
                    }
                    Text("While a timer is active, the last-known-alive time is saved to current.csv at this interval so tracking can be recovered after a crash or power loss.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button("Save") { onSave(config) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 420)
    }
}

// MARK: - Dialog window helper

final class DialogWindow {
    static func show<V: View>(title: String, view: V) -> NSWindow {
        let host = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: host)
        window.title = title
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.center()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return window
    }
}
