import Foundation
import CoreGraphics

final class IdleMonitor {
    private var timer: Timer?
    /// Called with current idle seconds once per tick.
    var onTick: ((TimeInterval) -> Void)?

    func start(interval: TimeInterval = 60) {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.onTick?(Self.systemIdleSeconds())
        }
        RunLoop.main.add(timer!, forMode: .common)
        // also fire once right away
        onTick?(Self.systemIdleSeconds())
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    static func systemIdleSeconds() -> TimeInterval {
        // HID idle time across any input device
        let anyEventType = CGEventType(rawValue: ~0)!
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyEventType)
    }
}
