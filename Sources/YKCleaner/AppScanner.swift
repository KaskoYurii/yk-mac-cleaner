import AppKit
import CoreServices

struct InstalledApp: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let name: String
    let bundleID: String?
    let version: String?
    let lastUsed: Date?
}

/// A file or folder that belongs to an app (the bundle itself or leftover data).
struct AppFile: Identifiable, Hashable, Sendable {
    var id: URL { url }
    let url: URL
    let kind: String
    let size: Int64
    let isDirectory: Bool
    /// Found only by app *name* (less certain) — unticked by default.
    let matchedByName: Bool
}

struct AppDetails: Sendable {
    let appSize: Int64
    let files: [AppFile]
    var dataSize: Int64 { files.reduce(0) { $0 + $1.size } }
}

enum AppScanner {
    static let ownBundleID = Bundle.main.bundleIdentifier ?? "com.yk.cleaner"

    private static var home: URL { FileManager.default.homeDirectoryForCurrentUser }

    static var appFolders: [URL] {
        [URL(fileURLWithPath: "/Applications", isDirectory: true),
         home.appendingPathComponent("Applications", isDirectory: true)]
    }

    // MARK: Installed apps

    static func listApps() -> [InstalledApp] {
        let fm = FileManager.default
        var result: [InstalledApp] = []
        var seen = Set<String>()

        func consider(_ url: URL) {
            guard url.pathExtension == "app" else { return }
            let resolved = url.resolvingSymlinksInPath().path
            guard !resolved.hasPrefix("/System/"), seen.insert(resolved).inserted else { return }
            let bundle = Bundle(url: url)
            let id = bundle?.bundleIdentifier
            if id == ownBundleID || id == "com.apple.Safari" { return }
            result.append(InstalledApp(
                url: url,
                name: url.deletingPathExtension().lastPathComponent,
                bundleID: id,
                version: bundle?.infoDictionary?["CFBundleShortVersionString"] as? String,
                lastUsed: lastUsedDate(url)))
        }

        for folder in appFolders {
            guard let children = try? fm.contentsOfDirectory(
                at: folder, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]) else { continue }
            for child in children {
                if child.pathExtension == "app" {
                    consider(child)
                } else if child.lastPathComponent != "Utilities",
                          (try? child.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true,
                          let sub = try? fm.contentsOfDirectory(at: child, includingPropertiesForKeys: nil,
                                                                options: [.skipsHiddenFiles]) {
                    sub.forEach(consider) // e.g. /Applications/Adobe Foo/Foo.app
                }
            }
        }
        return result.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func lastUsedDate(_ url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return MDItemCopyAttribute(item, kMDItemLastUsedDate) as? Date
    }

    // MARK: Leftover data

    static func details(for app: InstalledApp, otherBundleIDs: Set<String>) -> AppDetails {
        AppDetails(appSize: Scanner.size(of: app.url), files: leftovers(for: app, others: otherBundleIDs))
    }

    /// ~/Library folders where apps keep data, matched by bundle identifier.
    private static let libraryDirs: [(path: String, kind: String)] = [
        ("Application Support", "Application Support"),
        ("Caches", "Cache"),
        ("Containers", "Container"),
        ("Application Scripts", "Scripts"),
        ("Saved Application State", "Saved State"),
        ("Preferences", "Preferences"),
        ("Preferences/ByHost", "Preferences"),
        ("HTTPStorages", "Web Data"),
        ("WebKit", "Web Data"),
        ("Cookies", "Cookies"),
        ("Logs", "Logs"),
        ("LaunchAgents", "Launch Agent"),
    ]

    static func leftovers(for app: InstalledApp, others: Set<String>) -> [AppFile] {
        let fm = FileManager.default
        let lib = home.appendingPathComponent("Library", isDirectory: true)
        var found: [URL: (kind: String, byName: Bool)] = [:]

        if let id = app.bundleID?.lowercased(), !id.isEmpty {
            // Don't claim data of another installed app whose id extends this one
            // (e.g. com.google.Chrome vs com.google.Chrome.canary).
            func belongsToOther(_ name: String) -> Bool {
                others.contains { o in o != id && o.hasPrefix(id + ".") && (name == o || name.hasPrefix(o + ".")) }
            }
            for dir in libraryDirs {
                let folder = lib.appendingPathComponent(dir.path, isDirectory: true)
                guard let names = try? fm.contentsOfDirectory(atPath: folder.path) else { continue }
                for name in names {
                    let n = name.lowercased()
                    guard n == id || n.hasPrefix(id + "."), !belongsToOther(n) else { continue }
                    found[folder.appendingPathComponent(name)] = (dir.kind, false)
                }
            }
            let groups = lib.appendingPathComponent("Group Containers", isDirectory: true)
            if let names = try? fm.contentsOfDirectory(atPath: groups.path) {
                for name in names {
                    let n = name.lowercased()
                    if n.hasSuffix("." + id) || n == "group." + id {
                        found[groups.appendingPathComponent(name)] = ("Group Container", false)
                    }
                }
            }
        }

        // Less certain: folders named exactly like the app.
        if app.name.count >= 4 {
            for (dir, kind) in [("Application Support", "Application Support"), ("Caches", "Cache"), ("Logs", "Logs")] {
                let url = lib.appendingPathComponent(dir).appendingPathComponent(app.name)
                if found[url] == nil, fm.fileExists(atPath: url.path) { found[url] = (kind, true) }
            }
        }

        return found.map { url, info in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            return AppFile(url: url, kind: info.kind, size: Scanner.size(of: url),
                           isDirectory: isDir, matchedByName: info.byName)
        }
        .sorted { $0.size > $1.size }
    }
}

// MARK: - Moving to Trash

enum AppTrasher {
    /// Moves items to the Trash. Items the user can't move directly (e.g. apps
    /// installed by an admin package) are retried through Finder, which asks for
    /// the password itself.
    static func moveToTrash(_ urls: [URL]) -> (moved: [URL], failed: [URL]) {
        var moved: [URL] = []
        var retry: [URL] = []
        for url in urls {
            guard isAllowed(url) else { continue }
            do {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                moved.append(url)
            } catch {
                retry.append(url)
            }
        }
        if !retry.isEmpty { finderDelete(retry) }
        var failed: [URL] = []
        for url in retry {
            if FileManager.default.fileExists(atPath: url.path) { failed.append(url) } else { moved.append(url) }
        }
        return (moved, failed)
    }

    /// Only app folders and the user's Library are ever touched.
    static func isAllowed(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let roots = ["/Applications/", home + "/Applications/", home + "/Library/"]
        return roots.contains { path.hasPrefix($0) && path.count > $0.count }
    }

    private static func finderDelete(_ urls: [URL]) {
        func escape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        }
        var args = ["-e", "tell application \"Finder\""]
        for url in urls {
            args += ["-e", "try", "-e", "delete (POSIX file \"\(escape(url.path))\" as alias)", "-e", "end try"]
        }
        args += ["-e", "end tell"]
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = args
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
        process.waitUntilExit()
    }
}
