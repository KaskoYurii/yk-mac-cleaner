import AppKit
import SwiftUI

func openFullDiskAccessSettings() {
    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!)
}

struct ContentView: View {
    @Bindable var model: CleanerModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HeroView(model: model)
                    .padding(.bottom, 12)

                SectionHeader(title: "Your Mac")
                CategoryGrid(model: model, categories: model.categories.filter { !$0.requiresAdmin })

                SectionHeader(title: "System", subtitle: "Asks for your administrator password")
                    .padding(.top, 12)
                CategoryGrid(model: model, categories: model.categories.filter(\.requiresAdmin))
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 24)
            .frame(maxWidth: 1100)
            .frame(maxWidth: .infinity)
        }
        .hardTopScrollEdge()
        // Floating details panel: slides over the content instead of resizing it,
        // so the grid never reflows (no column jumps, no blinking, no lag).
        .overlay(alignment: .trailing) {
            if model.showInspector {
                DetailsPanel(model: model)
                    .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .smooth(duration: 0.3), value: model.showInspector)
        // Coming back from System Settings: rescan so newly granted access unlocks the cards.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            guard model.awaitingFullDiskAccess, !model.isBusy else { return }
            model.awaitingFullDiskAccess = false
            Task { await model.scan(keepingReport: true) }
        }
        .confirmationDialog("Delete \(Format.bytes(model.selectedTotal)) of junk?",
                            isPresented: $model.showCleanConfirmation) {
            Button("Delete \(Format.bytes(model.selectedTotal))", role: .destructive) {
                Task { await model.clean() }
            }
        } message: {
            Text("Selected items are removed permanently and can't be restored. Quit apps first for the best result.")
        }
    }
}

private struct SectionHeader: View {
    let title: String
    var subtitle: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.title3.weight(.semibold))
            if let subtitle {
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.leading, 4)
        .accessibilityAddTraits(.isHeader)
    }
}

private struct CategoryGrid: View {
    let model: CleanerModel
    let categories: [CleanCategory]

    private let spacing: CGFloat = 16

    var body: some View {
        // Container spacing matches the grid spacing so the cards sample one region
        // without blending into each other at rest.
        GlassGroup(spacing: spacing) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200, maximum: 400), spacing: spacing)],
                      spacing: spacing) {
                ForEach(categories) { cat in
                    CategoryCard(model: model, category: cat)
                }
            }
        }
    }
}

/// Opaque floating panel: cheap to animate (a single transform, no blur, no glass-on-glass).
private struct DetailsPanel: View {
    let model: CleanerModel

    var body: some View {
        CategoryInspector(model: model)
            .frame(width: 360)
            .frame(maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor))
            )
            .shadow(color: .black.opacity(0.25), radius: 24, x: 0, y: 8)
            .padding(12)
            .onExitCommand { model.showInspector = false }
    }
}
