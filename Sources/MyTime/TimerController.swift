import Foundation
import Combine

final class TimerController: ObservableObject {
    @Published private(set) var state: TimerState = .inactive
    @Published private(set) var currentEntry: CurrentEntry? = nil
    @Published private(set) var tickDate: Date = Date()

    let journal: Journal
    let currentStore: CurrentStore
    private var ticker: Timer?
    private(set) var lastStopTime: Date

    init(journal: Journal = Journal(), currentStore: CurrentStore = CurrentStore(), now: Date = Date()) {
        self.journal = journal
        self.currentStore = currentStore
        self.lastStopTime = now
        recoverOnBoot(now: now)
        startTicker()
    }

    // MARK: - Ticker (1s)
    private func startTicker() {
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async { self.tickDate = Date() }
        }
        RunLoop.main.add(ticker!, forMode: .common)
    }

    // MARK: - Boot recovery
    //
    // A leftover current.csv is either: (a) stale across midnight — close
    // it and go inactive; or (b) still on today — recover as paused so
    // the user can resume, adding away time to pausedSeconds, or stop.
    private func recoverOnBoot(now: Date) {
        guard let cur = currentStore.load() else { return }
        currentEntry = cur
        state = (cur.status == .active) ? .active : .paused
        if closeIfCrossedMidnight(now: now) { return }
        var recovered = cur
        recovered.status = .paused
        currentEntry = recovered
        state = .paused
        currentStore.save(recovered)
    }

    // MARK: - Internal tick
    //
    // Advance the in-flight entry's endTime to `now`. While paused, the
    // elapsed delta is added to pausedSeconds.
    @discardableResult
    private func tick(now: Date) -> CurrentEntry? {
        guard var e = currentEntry else { return nil }
        let delta = Int(now.timeIntervalSince(e.endTime))
        if delta > 0 {
            if e.status == .paused {
                e.pausedSeconds += delta
            }
            e.endTime = now
            currentEntry = e
        }
        return currentEntry
    }

    // MARK: - Heartbeat

    func heartbeat(now: Date = Date()) {
        guard currentEntry != nil else { return }
        if closeIfCrossedMidnight(now: now) { return }
        guard state == .active else { return }
        _ = tick(now: now)
        if let e = currentEntry { currentStore.save(e) }
    }

    /// If the entry's startTime is on a different calendar day than `now`,
    /// or its endTime has drifted past startTime's day, close it at endTime.
    @discardableResult
    private func closeIfCrossedMidnight(now: Date) -> Bool {
        guard let e = currentEntry else { return false }
        let cal = Calendar.current
        let sameDay = cal.isDate(e.startTime, inSameDayAs: now)
                      && cal.isDate(e.startTime, inSameDayAs: e.endTime)
        if sameDay { return false }
        finalize(e)
        return true
    }

    /// Append one journal row for the closed entry and clear current.csv.
    /// The row is attributed to the start-of-day of the entry's startTime.
    private func finalize(_ e: CurrentEntry) {
        let dur = max(0, Int(e.endTime.timeIntervalSince(e.startTime)) - e.pausedSeconds)
        let date = Calendar.current.startOfDay(for: e.startTime)
        journal.appendNew(TimerEntry(date: date, client: e.client,
                                     activity: e.activity, durationSeconds: dur))
        currentStore.clear()
        currentEntry = nil
        state = .inactive
        lastStopTime = e.endTime
    }

    // MARK: - Derived

    func displayElapsed(now: Date = Date()) -> Int {
        guard let e = currentEntry else { return 0 }
        let ref: Date = (e.status == .paused) ? e.endTime : now
        return max(0, Int(ref.timeIntervalSince(e.startTime)) - e.pausedSeconds)
    }

    func secondsSinceActive(now: Date = Date()) -> Int {
        if state == .active { return 0 }
        if state == .paused, let e = currentEntry {
            return Int(now.timeIntervalSince(e.endTime))
        }
        return Int(now.timeIntervalSince(lastStopTime))
    }

    // MARK: - Recent combos

    func recentCombos(limit: Int = 5) -> [(client: String, activity: String)] {
        let entries = journal.readAll().reversed()
        var seen = Set<String>()
        var out: [(String, String)] = []
        for e in entries {
            let key = "\(e.client)\u{1F}\(e.activity)"
            if seen.insert(key).inserted {
                out.append((e.client, e.activity))
            }
            if out.count >= limit { break }
        }
        return out
    }

    func knownClients() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in journal.readAll().reversed() {
            if !e.client.isEmpty && seen.insert(e.client).inserted { out.append(e.client) }
        }
        return out
    }

    func knownActivities() -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for e in journal.readAll().reversed() {
            if !e.activity.isEmpty && seen.insert(e.activity).inserted { out.append(e.activity) }
        }
        return out
    }

    // MARK: - Commands

    func startNew(client: String, activity: String = "", now: Date = Date()) {
        if state == .active || state == .paused {
            stop(now: now)
        }
        let e = CurrentEntry(startTime: now, client: client, activity: activity,
                             status: .active, endTime: now, pausedSeconds: 0)
        currentEntry = e
        state = .active
        currentStore.save(e)
    }

    func pause(now: Date = Date()) {
        guard state == .active, currentEntry != nil else { return }
        _ = tick(now: now)
        guard var e = currentEntry else { return }
        e.status = .paused
        currentEntry = e
        state = .paused
        currentStore.save(e)
    }

    func resume(now: Date = Date()) {
        guard state == .paused, currentEntry != nil else { return }
        _ = tick(now: now)
        guard var e = currentEntry else { return }
        e.status = .active
        currentEntry = e
        state = .active
        currentStore.save(e)
    }

    func stop(now: Date = Date()) {
        guard state == .active || state == .paused else { return }
        if state == .paused { resume(now: now) }
        _ = tick(now: now)
        guard let e = currentEntry else { return }
        finalize(e)
    }
}
