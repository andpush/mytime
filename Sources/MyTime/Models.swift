import Foundation

enum TimerState: String {
    case inactive
    case active
    case paused
}

/// A finalized row in `journal.csv`. Always has a real END_TIME (no parens)
/// and a computed DURATION_SECONDS.
struct TimerEntry: Equatable {
    var startTime: Date
    var client: String
    var activity: String
    var endTime: Date
    var durationSeconds: Int
    var pausedSeconds: Int

    init(startTime: Date, client: String, activity: String = "",
         endTime: Date, durationSeconds: Int, pausedSeconds: Int = 0) {
        self.startTime = startTime
        self.client = client
        self.activity = activity
        self.endTime = endTime
        self.durationSeconds = durationSeconds
        self.pausedSeconds = pausedSeconds
    }
}

/// The one-and-only row in `current.csv` representing the in-flight timer.
/// `endTime` is the last tick moment (heartbeat or state transition) — the
/// latest we know the user was still alive. On every tick, `endTime` is
/// advanced to `now`; while `status == .paused`, the elapsed delta is also
/// added to `pausedSeconds`.
struct CurrentEntry: Equatable {
    var startTime: Date
    var client: String
    var activity: String
    var status: TimerState   // only .active or .paused — never .inactive
    var endTime: Date
    var pausedSeconds: Int
}

struct AppConfig: Codable, Equatable {
    var remindTrackingMinutes: Int
    var idleToPauseMinutes: Int
    var pomodoroEnabled: Bool
    var pomodoroWorkMinutes: Int
    var launchAtLogin: Bool
    /// How often the active timer writes a heartbeat (parenthesized end_time)
    /// to the journal so the last known active moment survives a crash or
    /// power loss. Clamped to 1…60 minutes at read time.
    var heartbeatMinutes: Int

    static let defaults = AppConfig(
        remindTrackingMinutes: 15,
        idleToPauseMinutes: 15,
        pomodoroEnabled: false,
        pomodoroWorkMinutes: 25,
        launchAtLogin: false,
        heartbeatMinutes: 60
    )

    private enum CodingKeys: String, CodingKey {
        case remindTrackingMinutes, idleToPauseMinutes, pomodoroEnabled, pomodoroWorkMinutes, launchAtLogin, heartbeatMinutes
    }

    init(remindTrackingMinutes: Int, idleToPauseMinutes: Int, pomodoroEnabled: Bool, pomodoroWorkMinutes: Int, launchAtLogin: Bool, heartbeatMinutes: Int) {
        self.remindTrackingMinutes = remindTrackingMinutes
        self.idleToPauseMinutes = idleToPauseMinutes
        self.pomodoroEnabled = pomodoroEnabled
        self.pomodoroWorkMinutes = pomodoroWorkMinutes
        self.launchAtLogin = launchAtLogin
        self.heartbeatMinutes = heartbeatMinutes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.remindTrackingMinutes = try c.decode(Int.self, forKey: .remindTrackingMinutes)
        self.idleToPauseMinutes = try c.decode(Int.self, forKey: .idleToPauseMinutes)
        self.pomodoroEnabled = try c.decode(Bool.self, forKey: .pomodoroEnabled)
        self.pomodoroWorkMinutes = try c.decode(Int.self, forKey: .pomodoroWorkMinutes)
        self.launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        self.heartbeatMinutes = try c.decodeIfPresent(Int.self, forKey: .heartbeatMinutes) ?? 60
    }
}

enum PauseReason {
    case manual
    case idle(minutes: Int)
    case sleep
}
