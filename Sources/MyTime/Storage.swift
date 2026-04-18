import Foundation

enum Storage {
    static let dirURL: URL = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".config/mytime", isDirectory: true)
    }()
    static let journalURL = dirURL.appendingPathComponent("journal.csv")
    static let currentURL = dirURL.appendingPathComponent("current.csv")
    static let configURL = dirURL.appendingPathComponent("config.json")

    static func ensureDir() {
        try? FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
    }
}

// MARK: - ISO date formatting (local, no timezone)

enum LocalISO {
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        f.timeZone = TimeZone.current
        return f
    }()
    static func string(from date: Date) -> String { formatter.string(from: date) }
    static func date(from string: String) -> Date? { formatter.date(from: string) }
}

// MARK: - CSV field escaping

enum CSV {
    static func escape(_ field: String) -> String {
        if field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") {
            let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\""
        }
        return field
    }

    static func parseLine(_ line: String) -> [String] {
        return parseAll(line).first ?? []
    }

    static func parseAll(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var field = ""
        var row: [String] = []
        var inQuotes = false
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if inQuotes {
                if c == "\"" {
                    if i + 1 < chars.count && chars[i+1] == "\"" {
                        field.append("\"")
                        i += 2
                        continue
                    } else {
                        inQuotes = false
                        i += 1
                        continue
                    }
                } else {
                    field.append(c)
                    i += 1
                    continue
                }
            } else {
                if c == "\"" {
                    inQuotes = true
                    i += 1
                } else if c == "," {
                    row.append(field); field = ""
                    i += 1
                } else if c == "\r" {
                    i += 1
                } else if c == "\n" {
                    row.append(field); field = ""
                    rows.append(row); row = []
                    i += 1
                } else {
                    field.append(c)
                    i += 1
                }
            }
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows
    }
}

// MARK: - Journal I/O
//
// journal.csv is append-only and contains ONLY closed (finalized) rows.
// Every row has a real END_TIME, a computed DURATION_SECONDS, and
// PAUSED_SECONDS. In-flight timers live in current.csv, not here.

final class Journal {
    static let header = "START_TIME,CLIENT,ACTIVITY,END_TIME,DURATION_SECONDS,PAUSED_SECONDS"

    let url: URL
    init(url: URL = Storage.journalURL) { self.url = url }

    func ensureFile() {
        Storage.ensureDir()
        if !FileManager.default.fileExists(atPath: url.path) {
            try? (Journal.header + "\n").write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func readAll() -> [TimerEntry] {
        ensureFile()
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let rows = CSV.parseAll(text)
        var entries: [TimerEntry] = []
        let hasHeader = rows.first?.first?.uppercased() == "START_TIME"
        for (idx, row) in rows.enumerated() {
            if hasHeader && idx == 0 { continue }
            if row.isEmpty || (row.count == 1 && row[0].isEmpty) { continue }
            let padded = row + Array(repeating: "", count: max(0, 6 - row.count))
            guard let start = LocalISO.date(from: padded[0]),
                  let end = LocalISO.date(from: padded[3]) else { continue }
            let duration = Int(padded[4]) ?? 0
            let paused = Int(padded[5]) ?? 0
            entries.append(TimerEntry(
                startTime: start, client: padded[1], activity: padded[2],
                endTime: end, durationSeconds: duration, pausedSeconds: paused
            ))
        }
        return entries
    }

    func appendNew(_ entry: TimerEntry) {
        ensureFile()
        let line = Self.format(entry) + "\n"
        guard let data = line.data(using: .utf8) else { return }
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                return
            } catch {
                // fall through to rewrite on any I/O failure
            }
        }
        // Fallback: rewrite the whole file.
        var all = readAll()
        all.append(entry)
        var lines: [String] = [Journal.header]
        for e in all { lines.append(Self.format(e)) }
        try? (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    static func format(_ e: TimerEntry) -> String {
        return [
            CSV.escape(LocalISO.string(from: e.startTime)),
            CSV.escape(e.client),
            CSV.escape(e.activity),
            CSV.escape(LocalISO.string(from: e.endTime)),
            CSV.escape(String(e.durationSeconds)),
            CSV.escape(String(e.pausedSeconds))
        ].joined(separator: ",")
    }
}

// MARK: - Current-timer I/O
//
// current.csv holds at most one row — the in-flight timer. It is written
// on start, pause, resume, heartbeat, and midnight-split; deleted on stop.

final class CurrentStore {
    static let header = "START_TIME,CLIENT,ACTIVITY,STATUS,END_TIME,PAUSED_SECONDS"

    let url: URL
    init(url: URL = Storage.currentURL) { self.url = url }

    func load() -> CurrentEntry? {
        guard FileManager.default.fileExists(atPath: url.path),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let rows = CSV.parseAll(text)
        let hasHeader = rows.first?.first?.uppercased() == "START_TIME"
        for (idx, row) in rows.enumerated() {
            if hasHeader && idx == 0 { continue }
            if row.isEmpty || (row.count == 1 && row[0].isEmpty) { continue }
            let padded = row + Array(repeating: "", count: max(0, 6 - row.count))
            guard let start = LocalISO.date(from: padded[0]),
                  let end = LocalISO.date(from: padded[4]) else { continue }
            let status: TimerState = (padded[3].lowercased() == "paused") ? .paused : .active
            let paused = Int(padded[5]) ?? 0
            return CurrentEntry(startTime: start, client: padded[1], activity: padded[2],
                                status: status, endTime: end, pausedSeconds: paused)
        }
        return nil
    }

    func save(_ entry: CurrentEntry) {
        Storage.ensureDir()
        let line = [
            CSV.escape(LocalISO.string(from: entry.startTime)),
            CSV.escape(entry.client),
            CSV.escape(entry.activity),
            CSV.escape(entry.status.rawValue),
            CSV.escape(LocalISO.string(from: entry.endTime)),
            CSV.escape(String(entry.pausedSeconds))
        ].joined(separator: ",")
        let text = CurrentStore.header + "\n" + line + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
    }

    func clear() {
        try? FileManager.default.removeItem(at: url)
    }
}

// MARK: - Config I/O

final class ConfigStore {
    let url: URL
    init(url: URL = Storage.configURL) { self.url = url }

    func load() -> AppConfig {
        Storage.ensureDir()
        if let data = try? Data(contentsOf: url),
           let cfg = try? JSONDecoder().decode(AppConfig.self, from: data) {
            return cfg
        }
        let def = AppConfig.defaults
        save(def)
        return def
    }

    func save(_ cfg: AppConfig) {
        Storage.ensureDir()
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(cfg) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
