import Foundation

/// A group of junk files the app knows how to clean.
/// Each category points to one or more folders; the app only ever deletes
/// the *contents* of those folders, never the folders themselves.
struct CleanCategory: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let detail: String
    let symbol: String
    let roots: [URL]
    /// Needs an administrator password (system-wide folders owned by root).
    let requiresAdmin: Bool
    /// Selected for cleaning by default.
    let defaultSelected: Bool
    /// Only items not modified for at least this many days are offered.
    let minAgeDays: Int

    init(id: String, name: String, detail: String, symbol: String, roots: [URL],
         requiresAdmin: Bool = false, defaultSelected: Bool = true, minAgeDays: Int = 0) {
        self.id = id; self.name = name; self.detail = detail; self.symbol = symbol
        self.roots = roots; self.requiresAdmin = requiresAdmin
        self.defaultSelected = defaultSelected; self.minAgeDays = minAgeDays
    }
}

extension CleanCategory {
    static var all: [CleanCategory] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        func h(_ p: String) -> URL { home.appendingPathComponent(p, isDirectory: true) }

        return [
            CleanCategory(
                id: "trash", name: "Trash",
                detail: "Files you moved to the Trash. Requires Full Disk Access to read.",
                symbol: "trash", roots: [h(".Trash")]),
            CleanCategory(
                id: "userCaches", name: "App Caches",
                detail: "Caches created by apps and browsers (~/Library/Caches). Apps rebuild them as needed.",
                symbol: "archivebox", roots: [h("Library/Caches")]),
            CleanCategory(
                id: "userLogs", name: "Logs & Crash Reports",
                detail: "App log files and diagnostic reports (~/Library/Logs).",
                symbol: "doc.text", roots: [h("Library/Logs")]),
            CleanCategory(
                id: "xcode", name: "Xcode Junk",
                detail: "DerivedData, simulator caches and old device support files. Rebuilt automatically.",
                symbol: "hammer",
                roots: [h("Library/Developer/Xcode/DerivedData"),
                        h("Library/Developer/CoreSimulator/Caches"),
                        h("Library/Developer/Xcode/iOS DeviceSupport")]),
            CleanCategory(
                id: "devCaches", name: "Developer Caches",
                detail: "Package manager caches (npm, Gradle, CocoaPods, ~/.cache). Safe, but re-downloads may take time.",
                symbol: "shippingbox",
                roots: [h(".npm/_cacache"), h(".gradle/caches"), h(".cocoapods/repos"), h(".cache")],
                defaultSelected: false),
            CleanCategory(
                id: "temp", name: "Temporary Files",
                detail: "Your temporary folder. Only items untouched for 3+ days are shown.",
                symbol: "clock.arrow.circlepath",
                roots: [URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)],
                defaultSelected: false, minAgeDays: 3),
            CleanCategory(
                id: "systemCaches", name: "System Caches",
                detail: "System-wide caches (/Library/Caches). Asks for your administrator password.",
                symbol: "gearshape.2", roots: [URL(fileURLWithPath: "/Library/Caches", isDirectory: true)],
                requiresAdmin: true, defaultSelected: false),
            CleanCategory(
                id: "systemLogs", name: "System Logs",
                detail: "System-wide log files (/Library/Logs). Asks for your administrator password.",
                symbol: "list.bullet.rectangle", roots: [URL(fileURLWithPath: "/Library/Logs", isDirectory: true)],
                requiresAdmin: true, defaultSelected: false),
        ]
    }
}

/// One top-level entry inside a category root (a file or a folder).
struct ScanItem: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let root: URL
    let size: Int64
    let isDirectory: Bool
    var name: String { url.lastPathComponent }
}

struct CategoryResult: Sendable {
    var items: [ScanItem] = []
    /// A root folder exists but could not be read (usually missing Full Disk Access).
    var accessDenied = false
}

struct CleanReport: Sendable {
    var freed: Int64 = 0
    var removed = 0
    var failed: [String] = []
    var adminCancelled = false
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }
}
