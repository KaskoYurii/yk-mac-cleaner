import AppKit
import SwiftUI

/// App uninstaller: app list on the left, the selected app and its files on the right.
struct AppsView: View {
    @Bindable var apps: AppsModel

    var body: some View {
        HStack(spacing: 0) {
            AppList(apps: apps)
                .frame(width: 290)
            Divider()
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .confirmationDialog(confirmTitle, isPresented: $apps.showTrashConfirmation) {
            Button("Move to Trash", role: .destructive) {
                Task { await apps.trashSelected() }
            }
        } message: {
            Text("You can put items back from the Trash in Finder. Apps installed by an administrator may ask for your password.")
        }
    }

    private var confirmTitle: String {
        guard let app = apps.selectedApp else { return "Move to Trash?" }
        let n = apps.checkedFiles(for: app).count
        return apps.includesBundle(app)
            ? "Uninstall \(app.name) and \(n - 1) related item\(n - 1 == 1 ? "" : "s")?"
            : "Move \(n) item\(n == 1 ? "" : "s") of \(app.name) to the Trash?"
    }

    @ViewBuilder
    private var detail: some View {
        if let app = apps.selectedApp {
            AppDetailView(apps: apps, app: app)
                .id(app.url)
        } else if let r = apps.lastResult {
            ContentUnavailableView {
                Label(r.removedApp ? "\(r.appName) Uninstalled" : "Done", systemImage: "checkmark.circle")
            } description: {
                Text("Moved \(r.moved) item\(r.moved == 1 ? "" : "s") (\(Format.bytes(r.freed))) to the Trash."
                     + (r.failed > 0 ? " \(r.failed) couldn't be moved." : ""))
            }
        } else if apps.isLoading && apps.apps.isEmpty {
            ProgressView("Finding apps…")
        } else {
            ContentUnavailableView("Select an App", systemImage: "square.grid.2x2",
                                   description: Text("See its size and the data it left on your Mac."))
        }
    }
}

// MARK: - List

private struct AppList: View {
    @Bindable var apps: AppsModel

    var body: some View {
        list
            .safeAreaInset(edge: .top, spacing: 0) {
                VStack(spacing: 0) {
                    SearchField(text: $apps.search, prompt: "Search apps")
                        .padding(10)
                    Divider()
                }
                .background(.thinMaterial)
            }
    }

    private var list: some View {
        List(selection: Binding(get: { apps.selectedID }, set: { apps.select($0) })) {
            ForEach(apps.visibleApps) { app in
                AppRow(apps: apps, app: app)
                    .tag(app.url)
                    .contextMenu {
                        Button("Uninstall…") {
                            apps.select(app.url)
                            apps.requestTrash()
                        }
                        .disabled(!apps.canTrash(app))
                        if apps.isRunning(app) {
                            Button("Quit \(app.name)") { apps.quit(app) }
                        }
                        Divider()
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([app.url]) }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        .background(.thinMaterial)
        .onDeleteCommand { apps.requestTrash() }
        .overlay {
            if !apps.search.isEmpty && apps.visibleApps.isEmpty {
                ContentUnavailableView.search(text: apps.search)
            }
        }
        .hardTopScrollEdge()
    }
}

private struct AppRow: View {
    let apps: AppsModel
    let app: InstalledApp

    var body: some View {
        HStack(spacing: 10) {
            Image(nsImage: AppIconCache.icon(for: app.url))
                .resizable()
                .frame(width: 32, height: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name)
                    .lineLimit(1)
                HStack(spacing: 5) {
                    if apps.isRunning(app) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                            .accessibilityLabel("Running")
                    }
                    Text(apps.totalSize(app).map(Format.bytes) ?? "Measuring…")
                        .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
    }
}

// MARK: - Detail

private struct AppDetailView: View {
    let apps: AppsModel
    let app: InstalledApp
    @Namespace private var glass

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let r = apps.lastResult { resultBanner(r) }
                header
                if let d = apps.details[app.url] {
                    stats(d)
                    if apps.isRunning(app) { runningBanner }
                    filesCard
                    actions
                } else {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Measuring app and its data…").foregroundStyle(.secondary)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .hardTopScrollEdge()
    }

    private var header: some View {
        HStack(spacing: 18) {
            Image(nsImage: AppIconCache.icon(for: app.url))
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .black.opacity(0.2), radius: 8, y: 4)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(app.name)
                    .font(.system(.largeTitle, design: .rounded).weight(.bold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text([app.version.map { "Version \($0)" }, app.bundleID].compactMap { $0 }.joined(separator: " · "))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(lastUsedText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var lastUsedText: String {
        guard let date = app.lastUsed else { return "Last opened: unknown" }
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return "Last opened \(f.localizedString(for: date, relativeTo: .now))"
    }

    private func stats(_ d: AppDetails) -> some View {
        GlassGroup(spacing: 12) {
            HStack(spacing: 12) {
                StatChip(label: "App", value: d.appSize)
                StatChip(label: "Data", value: d.dataSize)
                StatChip(label: "Total", value: d.appSize + d.dataSize)
            }
        }
    }

    private var runningBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("\(app.name) is running. Quit it before removing.")
                .lineLimit(2)
            Spacer(minLength: 8)
            Button("Quit \(app.name)") { apps.quit(app) }
        }
        .padding(14)
        .glassCard(cornerRadius: 14, tint: .orange.opacity(0.15))
    }

    private func resultBanner(_ r: TrashResult) -> some View {
        HStack(spacing: 10) {
            Image(systemName: r.failed == 0 ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(r.failed == 0 ? .green : .orange)
            Text("Moved \(r.moved) item\(r.moved == 1 ? "" : "s") (\(Format.bytes(r.freed))) to the Trash."
                 + (r.failed > 0 ? " \(r.failed) couldn't be moved." : ""))
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(cornerRadius: 14, tint: .green.opacity(0.12))
    }

    private var filesCard: some View {
        let files = apps.files(for: app)
        let checked = apps.checkedFiles(for: app)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Files").font(.headline)
                Spacer()
                Text("\(checked.count) of \(files.count) selected · \(Format.bytes(checked.reduce(0) { $0 + $1.size }))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .padding(14)
            Divider()
            ForEach(files) { file in
                AppFileRow(apps: apps, app: app, file: file)
                if file.id != files.last?.id {
                    Divider().padding(.leading, 50)
                }
            }
        }
        .glassCard(cornerRadius: 18)
    }

    private var actions: some View {
        let checked = apps.checkedFiles(for: app)
        let size = Format.bytes(checked.reduce(0) { $0 + $1.size })
        let title = apps.includesBundle(app) ? "Uninstall · \(size)" : "Remove Data · \(size)"
        let enabled = apps.canTrash(app)
        return VStack(alignment: .leading, spacing: 10) {
            GlassGroup(spacing: 10) {
                HStack(spacing: 10) {
                    Button(action: apps.requestTrash) {
                        Label(title, systemImage: "trash")
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .pill()
                            .glassCapsule(tint: .red.opacity(enabled ? 0.85 : 0.35), interactive: enabled)
                            .glassMorphID("trash", in: glass)
                    }
                    .buttonStyle(.plain)
                    .disabled(!enabled)
                    .help("Move the selected files to the Trash (⌫)")

                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([app.url])
                    } label: {
                        Label("Show in Finder", systemImage: "folder")
                            .pill()
                            .glassCapsule(interactive: true)
                            .glassMorphID("finder", in: glass)
                    }
                    .buttonStyle(.plain)
                }
            }
            .animation(.bouncy(duration: 0.4), value: title)
            Text("Items go to the Trash, so you can put them back from Finder.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct StatChip: View {
    let label: String
    let value: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Format.bytes(value))
                .font(.system(.title2, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .frame(minWidth: 110, alignment: .leading)
        .glassCard(cornerRadius: 16)
        .accessibilityElement(children: .combine)
    }
}

private struct AppFileRow: View {
    let apps: AppsModel
    let app: InstalledApp
    let file: AppFile

    var body: some View {
        HStack(spacing: 10) {
            Toggle(isOn: Binding(
                get: { !apps.unchecked.contains(file.url) },
                set: { on in
                    if on { apps.unchecked.remove(file.url) } else { apps.unchecked.insert(file.url) }
                })) { EmptyView() }
                .toggleStyle(.checkbox)
                .labelsHidden()
                .accessibilityLabel("Include \(file.url.lastPathComponent)")
            Image(nsImage: file.url == app.url
                  ? AppIconCache.icon(for: app.url)
                  : FileIcon.icon(url: file.url, isDirectory: file.isDirectory))
                .resizable()
                .frame(width: 20, height: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(file.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(file.matchedByName ? "\(file.kind) · matched by name, check before removing" : file.kind)
                    .font(.caption)
                    .foregroundStyle(file.matchedByName ? .orange : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Text(Format.bytes(file.size))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .help(file.url.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file.url]) }
        }
    }
}

/// App icons are per-app, so cache by path.
@MainActor
enum AppIconCache {
    private static var cache: [String: NSImage] = [:]

    static func icon(for url: URL) -> NSImage {
        if let cached = cache[url.path] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache[url.path] = image
        return image
    }
}

/// Compact search field used above the app list.
private struct SearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 28)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        .onExitCommand { text = ""; focused = false }
    }
}
