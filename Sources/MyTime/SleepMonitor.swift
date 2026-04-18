import AppKit

final class SleepMonitor {
    var onWillSleep: (() -> Void)?
    var onDidWake: (() -> Void)?
    private var observers: [NSObjectProtocol] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.onWillSleep?()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.onWillSleep?()
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification,
                                        object: nil, queue: .main) { [weak self] _ in
            self?.onDidWake?()
        })
    }

    deinit {
        for o in observers { NSWorkspace.shared.notificationCenter.removeObserver(o) }
    }
}
