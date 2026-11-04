import Foundation
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

    private static let selectedKey = "selectedCategories"

    init() {
        if let saved = UserDefaults.standard.stringArray(forKey: Self.selectedKey) {
            selected = Set(saved)
        } else {
            selected = Set(CleanCategory.all.filter(\.defaultSelected).map(\.id))
        }
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
            for await (id, result) in group {
                results[id] = result
                scanning.remove(id)
            }
        }
    }

    func clean() async {
        guard canClean else { return }
        isCleaning = true
        let jobs: [(CleanCategory, [ScanItem])] = categories
            .filter { selected.contains($0.id) }
            .map { ($0, cleanableItems(for: $0)) }
            .filter { !$0.1.isEmpty }
        let report = await Task.detached(priority: .userInitiated) { Cleaner.clean(jobs) }.value
        isCleaning = false
        finishedReport = report
        await scan(keepingReport: true)
    }
}
