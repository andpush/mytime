import AppKit
import SwiftUI

final class StatusItemController: NSObject {
    private var statusItem: NSStatusItem!
    let controller: TimerController
    let configStore: ConfigStore
    let notif: NotificationManager
    var config: AppConfig

    var openStart: (() -> Void)?
    var openSettings: (() -> Void)?
    var openReports: (() -> Void)?
    var openJournal: (() -> Void)?
    var quitApp: (() -> Void)?

    private var menu: NSMenu!
    private var uiTimer: Timer?

    init(controller: TimerController, configStore: ConfigStore, notif: NotificationManager, config: AppConfig) {
        self.controller = controller
        self.configStore = configStore
        self.notif = notif
        self.config = config
        super.init()
        setup()
    }

    private func setup() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "clock", accessibilityDescription: "MyTime")
            button.imagePosition = .imageLeading
            button.title = ""
        }
        menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
        refreshTitle()
        startUITicker()
    }

    private func startUITicker() {
        uiTimer?.invalidate()
        uiTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.refreshTitle()
        }
        RunLoop.main.add(uiTimer!, forMode: .common)
    }

    func setConfig(_ cfg: AppConfig) { self.config = cfg }

    func refreshTitle() {
        guard let button = statusItem.button else { return }
        let s = controller.state
        let elapsed = controller.displayElapsed()
        let elapsedStr = formatElapsed(elapsed)
        switch s {
        case .inactive:
            button.title = ""
        case .active:
            button.title = " \(elapsedStr)"
        case .paused:
            button.title = " ⏸ \(elapsedStr)"
        }
    }

    private func formatElapsed(_ s: Int) -> String {
        let h = s / 3600, m = (s % 3600) / 60, sec = s % 60
        return String(format: "%02d:%02d:%02d", h, m, sec)
    }

    // MARK: - Menu building

    func rebuildMenu() {
        menu.removeAllItems()
        let s = controller.state
        let e = controller.currentEntry

        if !notif.authorized {
            let item = NSMenuItem(title: "⚠️ Enable Notifications…", action: #selector(openNotifSettings), keyEquivalent: "")
            item.target = self
            menu.addItem(item)
            menu.addItem(NSMenuItem.separator())
        }

        if s == .active, let e = e {
            let label = formatLabel(e)
            let pauseItem = NSMenuItem(title: "⏸ Pause \(label)", action: #selector(pauseTimer), keyEquivalent: "")
            pauseItem.target = self
            menu.addItem(pauseItem)
            let stopItem = NSMenuItem(title: "⏹ Stop \(label)", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            menu.addItem(NSMenuItem.separator())
        } else if s == .paused, let e = e {
            let label = formatLabel(e)
            let resumeItem = NSMenuItem(title: "▶ Resume \(label)", action: #selector(resumeTimer), keyEquivalent: "")
            resumeItem.target = self
            menu.addItem(resumeItem)
            let stopItem = NSMenuItem(title: "⏹ Stop \(label)", action: #selector(stopTimer), keyEquivalent: "")
            stopItem.target = self
            menu.addItem(stopItem)
            menu.addItem(NSMenuItem.separator())
        }

        let startNew = NSMenuItem(title: "▶ Start New Timer…", action: #selector(onStartNew), keyEquivalent: "n")
        startNew.target = self
        menu.addItem(startNew)

        let recents = controller.recentCombos(limit: 5)
        if !recents.isEmpty {
            menu.addItem(NSMenuItem.separator())
            for r in recents {
                let label = r.activity.isEmpty ? r.client : "\(r.client) - \(r.activity)"
                let item = NSMenuItem(title: "▶ Start \(label)", action: #selector(onStartRecent(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = ["client": r.client, "activity": r.activity]
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())
        let showJournal = NSMenuItem(title: "Show Journal", action: #selector(onShowJournal), keyEquivalent: "j")
        showJournal.target = self
        menu.addItem(showJournal)
        let reports = NSMenuItem(title: "View Reports", action: #selector(onReports), keyEquivalent: "r")
        reports.target = self
        menu.addItem(reports)

        menu.addItem(NSMenuItem.separator())
        let settings = NSMenuItem(title: "Settings…", action: #selector(onSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: "Quit MyTime", action: #selector(onQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
    }

    private func formatLabel(_ e: CurrentEntry) -> String {
        e.activity.isEmpty ? e.client : "\(e.client) - \(e.activity)"
    }

    // MARK: - Actions

    @objc private func pauseTimer() { controller.pause() ; refreshTitle() }
    @objc private func resumeTimer() { controller.resume(); refreshTitle() }
    @objc private func stopTimer() { controller.stop(); refreshTitle() }
    @objc private func onStartNew() { openStart?() }
    @objc private func onStartRecent(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: String] else { return }
        controller.startNew(client: info["client"] ?? "", activity: info["activity"] ?? "")
        refreshTitle()
    }
    @objc private func onShowJournal() { openJournal?() }
    @objc private func onReports() { openReports?() }
    @objc private func onSettings() { openSettings?() }
    @objc private func onQuit() { quitApp?() }
    @objc private func openNotifSettings() {
        notif.openSystemNotificationSettings()
        notif.requestAuthorization()
    }
}

extension StatusItemController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        notif.refreshAuthorization()
        rebuildMenu()
    }
}
