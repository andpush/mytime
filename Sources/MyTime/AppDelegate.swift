import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    let journal = Journal()
    let configStore = ConfigStore()
    let controller: TimerController
    let notif = NotificationManager.shared
    let idle = IdleMonitor()
    let sleep = SleepMonitor()
    let autostart = AutostartManager()

    var statusCtl: StatusItemController!
    var reportsCtl: ReportsWindowController!

    private var config: AppConfig
    private var startWindow: NSWindow?
    private var settingsWindow: NSWindow?

    private var lastIdlePauseTriggered: Bool = false
    private var reminderTimer: Timer?
    private var pomodoroWatch: Timer?
    private var heartbeatTimer: Timer?

    override init() {
        self.config = configStore.load()
        self.controller = TimerController(journal: journal)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        autostart.apply(enabled: config.launchAtLogin)

        notif.configure()
        notif.requestAuthorization()
        notif.onResumeTapped = { [weak self] in self?.resumeFromNotif() }
        notif.onStopTapped = { [weak self] in self?.stopFromNotif() }

        statusCtl = StatusItemController(controller: controller, configStore: configStore,
                                         notif: notif, config: config)
        statusCtl.openStart = { [weak self] in self?.showStartDialog() }
        statusCtl.openSettings = { [weak self] in self?.showSettingsDialog() }
        statusCtl.openReports = { [weak self] in self?.showReports() }
        statusCtl.openJournal = { [weak self] in self?.openJournalInDefaultApp() }
        statusCtl.quitApp = { NSApp.terminate(nil) }

        reportsCtl = ReportsWindowController(journal: journal)

        // Idle monitor
        idle.onTick = { [weak self] seconds in self?.handleIdleTick(seconds: seconds) }
        idle.start(interval: 60)

        // Sleep monitor
        sleep.onWillSleep = { [weak self] in self?.handleSleep() }
        sleep.onDidWake = { [weak self] in self?.handleWake() }
        sleep.start()

        // Reminder timer (every 30s, check)
        reminderTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.checkReminder()
        }
        RunLoop.main.add(reminderTimer!, forMode: .common)

        // Pomodoro watcher
        pomodoroWatch = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            self?.checkPomodoro()
        }
        RunLoop.main.add(pomodoroWatch!, forMode: .common)

        // Crash-recovery heartbeat
        scheduleHeartbeat()

        statusCtl.rebuildMenu()
    }

    private func scheduleHeartbeat() {
        heartbeatTimer?.invalidate()
        let minutes = max(1, min(60, config.heartbeatMinutes))
        let interval = TimeInterval(minutes * 60)
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.controller.heartbeat()
        }
        if let t = heartbeatTimer {
            RunLoop.main.add(t, forMode: .common)
        }
    }

    // MARK: - Menu handlers

    private func showStartDialog() {
        if let w = startWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        let clients = controller.knownClients()
        let activities = controller.knownActivities()
        var windowRef: NSWindow?
        let view = StartTimerView(clients: clients, activities: activities, onStart: { [weak self] c, a in
            self?.controller.startNew(client: c, activity: a)
            self?.statusCtl.refreshTitle()
            windowRef?.close()
            self?.startWindow = nil
        }, onCancel: { [weak self] in
            windowRef?.close()
            self?.startWindow = nil
        })
        let w = DialogWindow.show(title: "Start New Timer", view: view)
        windowRef = w
        startWindow = w
    }

    private func showSettingsDialog() {
        if let w = settingsWindow { NSApp.activate(ignoringOtherApps: true); w.makeKeyAndOrderFront(nil); return }
        var windowRef: NSWindow?
        let view = SettingsView(config: config, onSave: { [weak self] cfg in
            guard let self = self else { return }
            let autostartChanged = cfg.launchAtLogin != self.config.launchAtLogin
            let heartbeatChanged = cfg.heartbeatMinutes != self.config.heartbeatMinutes
            self.config = cfg
            self.configStore.save(cfg)
            self.statusCtl.setConfig(cfg)
            if autostartChanged {
                self.autostart.apply(enabled: cfg.launchAtLogin)
            }
            if heartbeatChanged {
                self.scheduleHeartbeat()
            }
            windowRef?.close()
            self.settingsWindow = nil
        }, onCancel: { [weak self] in
            windowRef?.close()
            self?.settingsWindow = nil
        })
        let w = DialogWindow.show(title: "MyTime Settings", view: view)
        windowRef = w
        settingsWindow = w
    }

    private func showReports() {
        reportsCtl.show()
    }

    private func openJournalInDefaultApp() {
        journal.ensureFile()
        NSWorkspace.shared.open(journal.url)
    }

    // MARK: - Notification reactions

    private func resumeFromNotif() {
        if controller.state == .paused {
            controller.resume()
            statusCtl.refreshTitle()
        }
    }

    private func stopFromNotif() {
        if controller.state == .active || controller.state == .paused {
            controller.stop()
            statusCtl.refreshTitle()
        }
    }

    // MARK: - Idle / sleep handling

    private func handleIdleTick(seconds: TimeInterval) {
        let threshold = TimeInterval(max(1, config.idleToPauseMinutes) * 60)
        if controller.state == .active && seconds >= threshold {
            if !lastIdlePauseTriggered {
                lastIdlePauseTriggered = true
                let pausedAt = Date().addingTimeInterval(-seconds)
                controller.pause(now: pausedAt)
                statusCtl.refreshTitle()
                if let e = controller.currentEntry {
                    notif.postAutoPause(reason: .idle(minutes: Int(seconds / 60)),
                                        client: e.client, activity: e.activity)
                }
            }
        } else if seconds < threshold {
            lastIdlePauseTriggered = false
        }
    }

    private func handleSleep() {
        if controller.state == .active {
            controller.pause()
            statusCtl.refreshTitle()
            if let e = controller.currentEntry {
                notif.postAutoPause(reason: .sleep, client: e.client, activity: e.activity)
            }
        }
    }

    private func handleWake() {
        // stay paused; notification tells user to resume
        statusCtl.refreshTitle()
    }

    // MARK: - Reminder / pomodoro

    private var lastReminderAt: Date = .distantPast

    private func checkReminder() {
        let interval = TimeInterval(max(1, config.remindTrackingMinutes) * 60)
        let since = controller.secondsSinceActive()
        if Double(since) >= interval,
           Date().timeIntervalSince(lastReminderAt) >= interval {
            notif.postRemind()
            lastReminderAt = Date()
        }
    }

    private func checkPomodoro() {
        guard config.pomodoroEnabled,
              controller.state == .active,
              let e = controller.currentEntry else { return }
        let threshold = config.pomodoroWorkMinutes * 60
        let elapsed = controller.displayElapsed()
        if elapsed >= threshold {
            let client = e.client
            let activity = e.activity
            controller.stop()
            statusCtl.refreshTitle()
            notif.postPomodoroFinished(client: client, activity: activity)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }
}
