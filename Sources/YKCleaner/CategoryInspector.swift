import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// Trailing inspector listing the items of one category.
/// Native checkboxes, multi-selection, Space for Quick Look, right-click actions.
struct CategoryInspector: View {
    @Bindable var model: CleanerModel
    @State private var selection = Set<URL>()
    @State private var previewURL: URL?

    var body: some View {
        if let category = model.inspectorCategory {
            content(for: category)
        } else {
            ContentUnavailableView("No Category", systemImage: "sidebar.trailing")
        }
    }

    /// Everything lives in one List so it is laid out below the toolbar correctly
    /// (the List manages the top safe area); the header is just the first row.
    private func content(for category: CleanCategory) -> some View {
        let items = model.items(for: category)
        let showsItems = !model.scanning.contains(category.id) && !model.isLocked(category) && !items.isEmpty
        return List(selection: $selection) {
            header(category)
                .listRowSeparator(.hidden)
                .selectionDisabled()

            if model.scanning.contains(category.id) {
                ProgressView("Scanning…")
                    .frame(maxWidth: .infinity, minHeight: 240)
                    .selectionDisabled()
            } else if model.isLocked(category) {
                ContentUnavailableView {
                    Label("Full Disk Access Needed", systemImage: "lock.shield")
                } description: {
                    Text("Turn on YK Cleaner in Privacy & Security › Full Disk Access, then come back. It checks again on its own.")
                } actions: {
                    Button("Open Privacy Settings", action: model.openFullDiskAccess)
                }
                .frame(minHeight: 280)
                .selectionDisabled()
            } else if items.isEmpty {
                ContentUnavailableView("Already Clean", systemImage: "checkmark.seal",
                                       description: Text("Nothing to remove here."))
                    .frame(minHeight: 280)
                    .selectionDisabled()
            } else {
                Section {
                    ForEach(items) { item in
                        ItemRow(model: model, item: item)
                            .tag(item.url)
                    }
                } header: {
                    Text("Items")
                }
            }
        }
        .contextMenu(forSelectionType: URL.self) { urls in
            if !urls.isEmpty {
                Button("Include") { urls.forEach { model.excluded.remove($0) } }
                Button("Exclude") { urls.forEach { model.excluded.insert($0) } }
                Divider()
                Button("Quick Look") { previewURL = urls.first }
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting(Array(urls)) }
            }
        } primaryAction: { urls in
            previewURL = urls.first
        }
        .onKeyPress(.space) {
            guard let first = selection.first else { return .ignored }
            previewURL = first
            return .handled
        }
        .quickLookPreview($previewURL, in: items.map(\.url))
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                titleBar(category)
                Divider()
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showsItems {
                VStack(spacing: 0) {
                    Divider()
                    footer(items)
                }
                .background(.bar)
            }
        }
        // Swap the list wholesale when the category changes instead of
        // diffing and animating hundreds of row insertions/removals.
        .id(category.id)
        .transaction { $0.animation = nil }
        .onChange(of: category.id) { selection.removeAll() }
    }

    /// Pinned title bar: category switcher on the left, close button top-right.
    private func titleBar(_ category: CleanCategory) -> some View {
        HStack(spacing: 10) {
            Menu {
                Picker("Category", selection: Binding(
                    get: { category.id },
                    set: { model.inspectorCategoryID = $0 })) {
                    ForEach(model.categories) { cat in
                        Label(cat.name, systemImage: cat.symbol).tag(cat.id)
                    }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: category.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(category.tint.gradient, in: Circle())
                    Text(category.name)
                        .font(.headline)
                        .lineLimit(1)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Switch category")

            Spacer(minLength: 8)

            Button {
                model.showInspector = false
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
                    .background(Color.primary.opacity(0.08), in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Close (Esc)")
            .accessibilityLabel("Close details")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func header(_ category: CleanCategory) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(Format.bytes(model.size(of: category)))
                    .font(.system(.title, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer()
                Toggle("Clean", isOn: Binding(
                    get: { model.selected.contains(category.id) },
                    set: { _ in model.toggle(category) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
            }
            Text(category.detail)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 8)
    }

    private func footer(_ items: [ScanItem]) -> some View {
        let included = items.filter { !model.excluded.contains($0.url) }.count
        return HStack {
            Text("\(included) of \(items.count) included")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Include All") { items.forEach { model.excluded.remove($0.url) } }
            Button("Exclude All") { items.forEach { model.excluded.insert($0.url) } }
        }
        .controlSize(.small)
        .padding(12)
    }
}

private struct ItemRow: View {
    let model: CleanerModel
    let item: ScanItem

    var body: some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { !model.excluded.contains(item.url) },
                set: { on in
                    if on { model.excluded.remove(item.url) } else { model.excluded.insert(item.url) }
                })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Include \(item.name)")
            Image(nsImage: FileIcon.icon(for: item))
                .resizable()
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)
            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(item.url.path)
            Text(Format.bytes(item.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

/// Icons looked up per file *type* (folder, .log, .db …) and cached,
/// instead of a per-path lookup on every row render.
@MainActor
enum FileIcon {
    private static var cache: [String: NSImage] = [:]

    static func icon(for item: ScanItem) -> NSImage {
        icon(url: item.url, isDirectory: item.isDirectory)
    }

    static func icon(url: URL, isDirectory isDir: Bool) -> NSImage {
        let key = isDir ? "/dir" : url.pathExtension.lowercased()
        if let cached = cache[key] { return cached }
        let type: UTType = isDir ? .folder : (UTType(filenameExtension: key) ?? .data)
        let image = NSWorkspace.shared.icon(for: type)
        cache[key] = image
        return image
    }
}
