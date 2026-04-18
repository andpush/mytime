import Foundation
import Combine

final class TimerController: ObservableObject {
    @Published private(set) var state: TimerState = .inactive
    @Published private(set) var currentEntry: CurrentEntry? = nil
    @Published private(set) var tickDate: Date = Date()

    let journal: Journal
    let currentStore: CurrentStore
    private var ticker: Timer?
    private(set) var lastStopTime: Date = Date()

    init(journal: Journal = Journal(), currentStore: CurrentStore = CurrentStore()) {
        self.journal = journal
        self.currentStore = currentStore
        recoverOnBoot()
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
    // On every launch, any leftover in-flight timer is recovered into the
    // PAUSED state — the work is preserved, not closed. endTime stays at
    // whatever the last tick / heartbeat wrote, so the user can resume
    // (adds the away time to PAUSED_SECONDS) or stop without losing context.
    //
    // Idempotency guard: if current.csv's startTime matches the last journal
    // row's startTime, it means a previous stop() appended the journal row
    // but crashed before removing current.csv. Just delete current.csv.
    private func recoverOnBoot() {
        guard let cur = currentStore.load() else {
            if let last = journal.readAll().last { lastStopTime = last.endTime }
            return
        }
        let entries = journal.readAll()
        if let last = entries.last, last.startTime == cur.startTime {
            currentStore.clear()
            lastStopTime = last.endTime
            return
        }
        var recovered = cur
        recovered.status = .paused
        currentStore.save(recovered)
        currentEntry = recovered
        state = .paused
        lastStopTime = recovered.endTime
    }

    // MARK: - Internal tick
    //
    // Advance the in-flight entry's endTime to `now`. While paused, the
    // elapsed delta is added to pausedSeconds. Called by every mutating
    // command so the current.csv view is always fresh.
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
        guard state == .active, currentEntry != nil else { return }
        splitIfCrossedMidnight(now: now)
        _ = tick(now: now)
        if let e = currentEntry { currentStore.save(e) }
    }

    /// If the current entry spans one or more midnights before `now`, close
    /// it at midnight (append to journal) and open a fresh current entry
    /// starting at that midnight. Loops for the unusual multi-midnight case.
    private func splitIfCrossedMidnight(now: Date) {
        guard var e = currentEntry else { return }
        let cal = Calendar.current
        while let midnight = Self.nextMidnight(after: e.startTime, cal: cal),
              midnight <= now {
            // Close at midnight.
            let dur = max(0, Int(midnight.timeIntervalSince(e.startTime)) - e.pausedSeconds)
            let closed = TimerEntry(
                startTime: e.startTime, client: e.client, activity: e.activity,
                endTime: midnight, durationSeconds: dur, pausedSeconds: e.pausedSeconds
            )
            journal.appendNew(closed)
            // Open a fresh current entry at midnight with same identity.
            e = CurrentEntry(startTime: midnight, client: e.client, activity: e.activity,
                             status: .active, endTime: midnight, pausedSeconds: 0)
            currentEntry = e
            currentStore.save(e)
            lastStopTime = midnight
        }
    }

    private static func nextMidnight(after date: Date, cal: Calendar) -> Date? {
        let startOfDay = cal.startOfDay(for: date)
        return cal.date(byAdding: .day, value: 1, to: startOfDay)
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
        let dur = max(0, Int(e.endTime.timeIntervalSince(e.startTime)) - e.pausedSeconds)
        let closed = TimerEntry(
            startTime: e.startTime, client: e.client, activity: e.activity,
            endTime: e.endTime, durationSeconds: dur, pausedSeconds: e.pausedSeconds
        )
        journal.appendNew(closed)
        currentStore.clear()
        currentEntry = nil
        state = .inactive
        lastStopTime = e.endTime
    }
}
