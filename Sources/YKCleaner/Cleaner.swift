import Foundation

enum Cleaner {
    /// Deletes the given items. Every item must be a direct child of one of its
    /// category's roots — anything else is refused as a safety measure.
    static func clean(_ jobs: [(CleanCategory, [ScanItem])]) -> CleanReport {
        var report = CleanReport()
        var adminItems: [ScanItem] = []

        for (category, items) in jobs {
            for item in items where isSafe(item, in: category) {
                if category.requiresAdmin {
                    adminItems.append(item)
                } else {
                    do {
                        try FileManager.default.removeItem(at: item.url)
                        report.freed += item.size
                        report.removed += 1
                    } catch {
                        report.failed.append(item.url.path)
                    }
                }
            }
        }

        if !adminItems.isEmpty {
            switch removeWithAdmin(adminItems.map(\.url.path)) {
            case .cancelled:
                report.adminCancelled = true
            case .ran:
                for item in adminItems {
                    if FileManager.default.fileExists(atPath: item.url.path) {
                        report.failed.append(item.url.path)
                    } else {
                        report.freed += item.size
                        report.removed += 1
                    }
                }
            }
        }
        return report
    }

    private static func isSafe(_ item: ScanItem, in category: CleanCategory) -> Bool {
        let parent = item.url.deletingLastPathComponent().standardizedFileURL.path
        let root = item.root.standardizedFileURL.path
        return parent == root
            && category.roots.contains { $0.standardizedFileURL.path == root }
            && item.url.lastPathComponent != "."
            && item.url.lastPathComponent != ".."
    }

    private enum AdminResult { case ran, cancelled }

    /// Runs `rm -rf` for the paths with administrator privileges (macOS shows its own password prompt).
    private static func removeWithAdmin(_ paths: [String]) -> AdminResult {
        func shellQuote(_ s: String) -> String { "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'" }
        let command = "/bin/rm -rf -- " + paths.map(shellQuote).joined(separator: " ") + " 2>/dev/null; exit 0"
        let escaped = command
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escaped)\" with administrator privileges"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .cancelled
        }
        return process.terminationStatus == 0 ? .ran : .cancelled
    }
}
