import Foundation

/// Installs/removes a per-user LaunchAgent plist so MyTime starts on login.
/// Kept out of `Storage.swift` because it touches `~/Library/LaunchAgents`, not `~/.config/mytime`.
final class AutostartManager {
    static let label = "com.mytime.agent"

    private let fileManager: FileManager
    private let plistURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.plistURL = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Self.label).plist")
    }

    var isInstalled: Bool {
        fileManager.fileExists(atPath: plistURL.path)
    }

    func apply(enabled: Bool) {
        if enabled {
            install()
        } else {
            try? fileManager.removeItem(at: plistURL)
        }
    }

    private func install() {
        guard let executablePath = Bundle.main.executablePath ?? CommandLine.arguments.first else { return }
        let plist: [String: Any] = [
            "Label": Self.label,
            "ProgramArguments": [executablePath],
            "RunAtLoad": true,
            "KeepAlive": false
        ]
        let dir = plistURL.deletingLastPathComponent()
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: plistURL, options: .atomic)
        }
    }
}
