import AppKit
import Observation

@MainActor
@Observable
final class CleanerModel {
    let categories = CleanCategory.all
    var results: [String: CategoryResult] = [:] { didSet { recomputeSizes() } }
    var scanning: Set<String> = []
    var excluded: Set<URL> = [] { didSet { recomputeSizes() } }

    /// Cached per-category sizes (cleanable) and grand total, so views don't
    /// re-filter every item list on each render.
    private(set) var cleanableSizes: [String: Int64] = [:]
    private(set) var grandTotal: Int64 = 0
    var isCleaning = false

    /// Categories ticked for cleaning; remembered across launches.
    var selected: Set<String> {
        didSet { UserDefaults.standard.set(Array(selected), forKey: Self.selectedKey) }
    }

    // UI state shared between the window and the menu bar commands.
    var section: AppSection = .cleaner
    var showInspector = false
    var inspectorCategoryID: String?
    var showCleanConfirmation = false
    /// Result of the last clean, shown inline until dismissed or the next manual scan.
    var finishedReport: CleanReport?
    /// Set when we sent the user to the Full Disk Access settings; the next app activation rescans.
    var awaitingFullDiskAccess = false

    // Auto clean settings; remembered across launches.
    var autoCleanEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoCleanEnabled, forKey: "autoCleanEnabled")
            // The first automatic run comes one full interval after switching it on.
            if autoCleanEnabled && !oldValue { lastAutoClean = .now }
        }
    }
    /// Show the usual confirmation instead of deleting straight away.
    var autoCleanAsk: Bool { didSet { UserDefaults.standard.set(autoCleanAsk, forKey: "autoCleanAsk") } }
    var autoCleanEvery: Int { didSet { UserDefaults.standard.set(autoCleanEvery, forKey: "autoCleanEvery") } }
    var autoCleanUnit: AutoCleanUnit { didSet { UserDefaults.standard.set(autoCleanUnit.rawValue, forKey: "autoCleanUnit") } }
    private var lastAutoClean: Date? { didSet { UserDefaults.standard.set(lastAutoClean, forKey: "lastAutoClean") } }

    /// Opens the main window; set by the menu bar item, which outlives the window.
    @ObservationIgnored var showWindow: (() -> Void)?

    /// System items an admin `rm -rf` couldn't remove (protected by macOS). Hidden from later
    /// scans so they don't trigger a password prompt on every clean.
    private var protectedPaths: Set<String> {
        didSet { UserDefaults.standard.set(Array(protectedPaths), forKey: "protectedPaths") }
    }

    private static let selectedKey = "selectedCategories"

    init() {
        let defaults = UserDefaults.standard
        if let saved = defaults.stringArray(forKey: Self.selectedKey) {
            selected = Set(saved)
        } else {
            selected = Set(CleanCategory.all.filter(\.defaultSelected).map(\.id))
        }
        autoCleanEnabled = defaults.bool(forKey: "autoCleanEnabled")
        autoCleanAsk = defaults.object(forKey: "autoCleanAsk") as? Bool ?? true
        autoCleanEvery = max(1, defaults.integer(forKey: "autoCleanEvery"))
        autoCleanUnit = defaults.string(forKey: "autoCleanUnit").flatMap(AutoCleanUnit.init) ?? .day
        lastAutoClean = defaults.object(forKey: "lastAutoClean") as? Date
        protectedPaths = Set(defaults.stringArray(forKey: "protectedPaths") ?? [])
        Task { await runAutoCleanLoop() } // the model lives as long as the app
    }

    // MARK: Derived values

    var isScanning: Bool { !scanning.isEmpty }
    var isBusy: Bool { isScanning || isCleaning }
    var canClean: Bool { !isBusy && selectedTotal > 0 }

    func category(_ id: String) -> CleanCategory? { categories.first { $0.id == id } }

    var inspectorCategory: CleanCategory? {
        inspectorCategoryID.flatMap(category) ?? categories.first
    }

    func items(for category: CleanCategory) -> [ScanItem] {
        results[category.id]?.items ?? []
    }

    func cleanableItems(for category: CleanCategory) -> [ScanItem] {
        items(for: category).filter { !excluded.contains($0.url) }
    }

    func size(of category: CleanCategory) -> Int64 {
        cleanableSizes[category.id] ?? 0
    }

    private func recomputeSizes() {
        var sizes: [String: Int64] = [:]
        var grand: Int64 = 0
        for (id, result) in results {
            var cleanable: Int64 = 0
            for item in result.items {
                grand += item.size
                if !excluded.contains(item.url) { cleanable += item.size }
            }
            sizes[id] = cleanable
        }
        cleanableSizes = sizes
        grandTotal = grand
    }

    func isLocked(_ category: CleanCategory) -> Bool {
        results[category.id]?.accessDenied == true && items(for: category).isEmpty
    }

    var selectedTotal: Int64 {
        categories.filter { selected.contains($0.id) }.reduce(0) { $0 + size(of: $1) }
    }

    // MARK: Actions

    func toggle(_ category: CleanCategory) {
        if selected.contains(category.id) { selected.remove(category.id) } else { selected.insert(category.id) }
    }

    func selectAll() { selected = Set(categories.map(\.id)) }
    func deselectAll() { selected.removeAll() }

    func showDetails(for category: CleanCategory) {
        inspectorCategoryID = category.id
        showInspector = true
    }

    func openFullDiskAccess() {
        awaitingFullDiskAccess = true
        openFullDiskAccessSettings()
    }

    func requestClean() {
        if canClean { showCleanConfirmation = true }
    }

    func scan(keepingReport: Bool = false) async {
        guard !isScanning else { return }
        if !keepingReport { finishedReport = nil }
        excluded.removeAll()
        let cats = categories
        scanning = Set(cats.map(\.id))
        await withTaskGroup(of: (String, CategoryResult).self) { group in
            for cat in cats {
                group.addTask { (cat.id, Scanner.scan(cat)) }
            }
            for await (id, var result) in group {
                result.items.removeAll { protectedPaths.contains($0.url.path) }
                results[id] = result
                scanning.remove(id)
            }
        }
    }

    func clean() async {
        guard canClean else { return }
        await clean(categories.filter { selected.contains($0.id) })
    }

    private func clean(_ cats: [CleanCategory]) async {
        let jobs: [(CleanCategory, [ScanItem])] = cats
            .map { ($0, cleanableItems(for: $0)) }
            .filter { !$0.1.isEmpty }
        guard !jobs.isEmpty else { return }
        isCleaning = true
        let report = await Task.detached(priority: .userInitiated) { Cleaner.clean(jobs) }.value
        let adminPaths = Set(jobs.filter { $0.0.requiresAdmin }.flatMap { $0.1.map(\.url.path) })
        if !report.adminCancelled { protectedPaths.formUnion(report.failed.filter(adminPaths.contains)) }
        isCleaning = false
        finishedReport = report
        await scan(keepingReport: true)
    }

    // MARK: Auto clean

    var nextAutoClean: Date? {
        guard autoCleanEnabled, let lastAutoClean else { return nil }
        return lastAutoClean.addingTimeInterval(Double(autoCleanEvery) * autoCleanUnit.seconds)
    }

    /// Runs for the app's lifetime. Polling once a minute survives sleep/wake and settings
    /// changes; a run missed while the app was closed happens right after launch.
    private func runAutoCleanLoop() async {
        while !Task.isCancelled {
            if let next = nextAutoClean, next <= .now, !isBusy, !showCleanConfirmation {
                lastAutoClean = .now
                await scan()
                if autoCleanAsk {
                    section = .cleaner
                    requestClean()
                    if showCleanConfirmation {
                        showWindow?() // the confirmation lives in the window, which may be closed
                        NSApp.requestUserAttention(.criticalRequest)
                    }
                } else {
                    // No one is there to type a password, so admin-only areas are skipped.
                    await clean(categories.filter { selected.contains($0.id) && !$0.requiresAdmin })
                }
            }
            try? await Task.sleep(for: .seconds(60))
        }
    }
}

enum AutoCleanUnit: String, CaseIterable, Identifiable {
    case hour, day
    var id: Self { self }
    var seconds: TimeInterval { self == .hour ? 3600 : 86400 }
    func label(_ count: Int) -> String { count == 1 ? rawValue : rawValue + "s" }
}
