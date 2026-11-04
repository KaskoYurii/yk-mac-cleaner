import SwiftUI

@main
struct YKCleanerApp: App {
    @State private var model = CleanerModel()
    @State private var apps = AppsModel()

    var body: some Scene {
        Window("YK Cleaner", id: "main") {
            RootView(model: model, apps: apps)
                .frame(minWidth: 760, minHeight: 560)
        }
        .defaultSize(width: 1080, height: 780)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands { CleanerCommands(model: model, apps: apps) }
    }
}

/// Hosts both sections. Both stay alive (no rebuild, scroll position kept) and
/// cross-fade with a short directional slide; background and toolbar are shared,
/// so only the content changes.
struct RootView: View {
    @Bindable var model: CleanerModel
    @Bindable var apps: AppsModel
    @State private var appsVisited = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var onApps: Bool { model.section == .apps }

    var body: some View {
        ZStack {
            ContentView(model: model)
                .sectionVisibility(active: !onApps, offset: -24, reduceMotion: reduceMotion)

            if appsVisited {
                AppsView(apps: apps)
                    .sectionVisibility(active: onApps, offset: 24, reduceMotion: reduceMotion)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.2) : .smooth(duration: 0.35), value: model.section)
        .background { AuroraBackground().ignoresSafeArea() }
        .navigationTitle(onApps ? "Apps" : "YK Cleaner")
        .navigationSubtitle(subtitle)
        .toolbar { toolbar }
        .task { await model.scan() }
        .onChange(of: model.section, initial: true) { _, section in
            if section == .apps { model.showInspector = false }
            guard section == .apps, !appsVisited else { return }
            appsVisited = true
            Task { await apps.load() }
        }
    }

    private var subtitle: String {
        if onApps {
            return apps.isLoading ? "Measuring apps…" : "\(apps.apps.count) apps · \(Format.bytes(apps.totalSize))"
        }
        return model.isScanning ? "Scanning…" : "\(Format.bytes(model.selectedTotal)) selected"
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            Picker("Section", selection: $model.section) {
                Text("Cleaner").tag(AppSection.cleaner)
                Text("Apps").tag(AppSection.apps)
            }
            .pickerStyle(.segmented)
            .frame(width: 180)
            .help("Switch section (⌘1 / ⌘2)")
        }
        ToolbarItemGroup(placement: .primaryAction) {
            if onApps {
                Menu {
                    Picker("Sort By", selection: $apps.sort) {
                        ForEach(AppSort.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.inline)
                } label: {
                    Label("Sort", systemImage: "arrow.up.arrow.down")
                }
                .help("Sort apps")
                Button {
                    Task { await apps.load() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(apps.isLoading)
                .help("Scan apps again (⌘R)")
            } else {
                Button {
                    Task { await model.scan() }
                } label: {
                    Label("Rescan", systemImage: "arrow.clockwise")
                }
                .disabled(model.isBusy)
                .help("Scan again (⌘R)")
                Button {
                    model.showInspector.toggle()
                } label: {
                    Label("Details", systemImage: "sidebar.trailing")
                }
                .help("Show or hide details (⌥⌘I)")
            }
        }
    }
}

private extension View {
    /// Fades/slides a section in or out while keeping it alive.
    func sectionVisibility(active: Bool, offset: CGFloat, reduceMotion: Bool) -> some View {
        self
            .opacity(active ? 1 : 0)
            .offset(x: active || reduceMotion ? 0 : offset)
            .allowsHitTesting(active)
            .disabled(!active) // hidden section's keyboard shortcuts must not fire
            .accessibilityHidden(!active)
    }
}

/// Menu bar commands — every action in the window is reachable from the keyboard.
struct CleanerCommands: Commands {
    let model: CleanerModel
    let apps: AppsModel

    var body: some Commands {
        // Single-window utility: no "New Window".
        CommandGroup(replacing: .newItem) {}

        CommandGroup(before: .sidebar) {
            Button("Cleaner") { model.section = .cleaner }
                .keyboardShortcut("1")
            Button("Apps") { model.section = .apps }
                .keyboardShortcut("2")
            Divider()
        }

        CommandMenu("Clean") {
            Button("Rescan") {
                if model.section == .apps { Task { await apps.load() } } else { Task { await model.scan() } }
            }
            .keyboardShortcut("r")
            .disabled(model.section == .apps ? apps.isLoading : model.isBusy)

            Button("Clean Selected…") { model.requestClean() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(model.section != .cleaner || !model.canClean)

            Button("Uninstall Selected App…") { apps.requestTrash() }
                .disabled(model.section != .apps || apps.selectedApp.map { !apps.canTrash($0) } ?? true)
            Divider()
            Button("Select All Areas") { model.selectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(model.section != .cleaner)
            Button("Deselect All Areas") { model.deselectAll() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(model.section != .cleaner)
        }

        CommandGroup(after: .sidebar) {
            Button(model.showInspector ? "Hide Details" : "Show Details") {
                model.showInspector.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(model.section != .cleaner)
        }
    }
}
