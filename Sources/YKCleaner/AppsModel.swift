import AppKit
import Observation
import SwiftUI

enum AppSection: String, Hashable {
    case cleaner, apps
}

enum AppSort: String, CaseIterable, Identifiable {
    case size = "Size"
    case name = "Name"
    case lastUsed = "Last Opened"
    var id: Self { self }
}

struct TrashResult: Equatable {
    let appName: String
    let moved: Int
    let freed: Int64
    let failed: Int
    let removedApp: Bool
}

@MainActor
@Observable
final class AppsModel {
    var apps: [InstalledApp] = []
    var details: [URL: AppDetails] = [:]
    var isLoading = false
    var selectedID: URL?
    var search = ""
    var sort: AppSort = .size
    /// Files the user unticked (name-matched leftovers start unticked).
    var unchecked: Set<URL> = []
    var runningBundleIDs: Set<String> = []
    var showTrashConfirmation = false
    var isTrashing = false
    var lastResult: TrashResult?

    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        refreshRunning()
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    // MARK: Derived

    var selectedApp: InstalledApp? { apps.first { $0.url == selectedID } }

    /// First stage of loading: the app list itself hasn't arrived yet.
    var isListing: Bool { isLoading && apps.isEmpty }
    /// Second stage: apps are listed, sizes are still being measured.
    var isMeasuring: Bool { isLoading && !apps.isEmpty }
    var measuredCount: Int { details.count }

    func totalSize(_ app: InstalledApp) -> Int64? {
        details[app.url].map { $0.appSize + $0.dataSize }
    }

    var totalSize: Int64 { apps.reduce(0) { $0 + (totalSize($1) ?? 0) } }

    var visibleApps: [InstalledApp] {
        let filtered = search.isEmpty ? apps : apps.filter {
            $0.name.localizedCaseInsensitiveContains(search)
                || ($0.bundleID?.localizedCaseInsensitiveContains(search) ?? false)
        }
        switch sort {
        case .name:
            return filtered
        case .size:
            // Keep a stable order while sizes are still being calculated.
            if isLoading { return filtered }
            return filtered.sorted { (totalSize($0) ?? -1) > (totalSize($1) ?? -1) }
        case .lastUsed:
            return filtered.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    /// The app bundle itself first, then its leftover data.
    func files(for app: InstalledApp) -> [AppFile] {
        guard let d = details[app.url] else { return [] }
        let bundle = AppFile(url: app.url, kind: "Application", size: d.appSize, isDirectory: true, matchedByName: false)
        return [bundle] + d.files
    }

    func checkedFiles(for app: InstalledApp) -> [AppFile] {
        files(for: app).filter { !unchecked.contains($0.url) }
    }

    func includesBundle(_ app: InstalledApp) -> Bool { !unchecked.contains(app.url) }

    func isRunning(_ app: InstalledApp) -> Bool {
        app.bundleID.map(runningBundleIDs.contains) ?? false
    }

    func canTrash(_ app: InstalledApp) -> Bool {
        !isTrashing && details[app.url] != nil && !checkedFiles(for: app).isEmpty && !isRunning(app)
    }

    // MARK: Actions

    func select(_ id: URL?) {
        selectedID = id
        lastResult = nil
    }

    func refreshRunning() {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
    }

    func quit(_ app: InstalledApp) {
        guard let id = app.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }

    func requestTrash() {
        if let app = selectedApp, canTrash(app) { showTrashConfirmation = true }
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        lastResult = nil
        let list = await Task.detached(priority: .userInitiated) { AppScanner.listApps() }.value
        // Cross-fade from the placeholder rows to the real list.
        withAnimation(Self.motion(.smooth(duration: 0.4))) {
            apps = list
            details = [:]
            unchecked = []
        }
        if let id = selectedID, !list.contains(where: { $0.url == id }) { selectedID = nil }

        let ids = Set(list.compactMap { $0.bundleID?.lowercased() })
        await withTaskGroup(of: (URL, AppDetails).self) { group in
            var queue = list.makeIterator()
            for _ in 0..<4 {
                if let app = queue.next() {
                    group.addTask { (app.url, AppScanner.details(for: app, otherBundleIDs: ids)) }
                }
            }
            for await (url, d) in group {
                details[url] = d
                for file in d.files where file.matchedByName { unchecked.insert(file.url) }
                if let app = queue.next() {
                    group.addTask { (app.url, AppScanner.details(for: app, otherBundleIDs: ids)) }
                }
            }
        }
        // Sorting by size kicks in now; animate it so rows glide into place instead of jumping.
        withAnimation(Self.motion(.smooth(duration: 0.5))) { isLoading = false }
    }

    /// The animation, or a short fade when Reduce Motion is on.
    private static func motion(_ animation: Animation) -> Animation {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? .easeOut(duration: 0.15) : animation
    }

    func trashSelected() async {
        guard let app = selectedApp, canTrash(app) else { return }
        let files = checkedFiles(for: app)
        let urls = files.map(\.url)
        isTrashing = true
        let result = await Task.detached(priority: .userInitiated) { AppTrasher.moveToTrash(urls) }.value
        isTrashing = false

        let moved = Set(result.moved)
        let report = TrashResult(
            appName: app.name,
            moved: moved.count,
            freed: files.filter { moved.contains($0.url) }.reduce(0) { $0 + $1.size },
            failed: result.failed.count,
            removedApp: moved.contains(app.url))

        if report.removedApp {
            apps.removeAll { $0.url == app.url }
            details[app.url] = nil
            selectedID = nil
        } else {
            let ids = Set(apps.compactMap { $0.bundleID?.lowercased() })
            details[app.url] = await Task.detached { AppScanner.details(for: app, otherBundleIDs: ids) }.value
        }
        lastResult = report
    }
}
