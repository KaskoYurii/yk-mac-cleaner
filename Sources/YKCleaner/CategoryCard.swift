import AppKit
import SwiftUI

/// A glass card per category. The whole card is a Button that toggles selection;
/// details live in the inspector (via the info button, context menu, or ⌥⌘I).
struct CategoryCard: View {
    let model: CleanerModel
    let category: CleanCategory

    private var isOn: Bool { model.selected.contains(category.id) }
    private var isScanning: Bool { model.scanning.contains(category.id) }
    private var locked: Bool { model.isLocked(category) }
    private var itemCount: Int { model.items(for: category).count }

    var body: some View {
        Button {
            if locked { openFullDiskAccessSettings() } else { model.toggle(category) }
        } label: {
            content
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 148, alignment: .topLeading)
                .contentShape(RoundedRectangle(cornerRadius: 22))
                .glassCard(cornerRadius: 22, tint: isOn ? category.tint.opacity(0.22) : nil, interactive: true)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) { infoButton.padding(10) }
        .animation(.smooth(duration: 0.25), value: isOn)
        .contextMenu { menu }
        .help(category.detail)
        .accessibilityLabel(category.name)
        .accessibilityValue(accessibilityValue)
        .accessibilityHint(locked ? "Opens Full Disk Access settings" : "Toggles whether this area is cleaned")
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Image(systemName: category.symbol)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(category.tint.gradient, in: Circle())
                Spacer()
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isOn ? category.tint : .secondary)
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }

            Text(category.name)
                .font(.headline)
                .lineLimit(1)

            sizeView

            Text(caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .padding(.trailing, 28) // room for the info button
        }
    }

    @ViewBuilder
    private var sizeView: some View {
        if isScanning {
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Scanning").foregroundStyle(.secondary)
            }
            .font(.system(.title3, design: .rounded))
            .frame(height: 30, alignment: .leading)
        } else if locked {
            Label("Locked", systemImage: "lock.fill")
                .font(.system(.title3, design: .rounded).weight(.bold))
                .foregroundStyle(.orange)
                .frame(height: 30, alignment: .leading)
        } else {
            Text(Format.bytes(model.size(of: category)))
                .font(.system(.title, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .frame(height: 30, alignment: .leading)
        }
    }

    private var infoButton: some View {
        Button {
            model.showDetails(for: category)
        } label: {
            Image(systemName: "info")
                .font(.system(size: 11, weight: .bold))
                .frame(width: 24, height: 24)
                .contentShape(Circle())
                .glassCircle(interactive: true)
        }
        .buttonStyle(.plain)
        .disabled(isScanning || locked)
        .opacity(isScanning || locked ? 0 : 1)
        .help("Show items")
        .accessibilityLabel("Show \(category.name) items")
    }

    @ViewBuilder
    private var menu: some View {
        if locked {
            Button("Grant Full Disk Access…", action: openFullDiskAccessSettings)
        } else {
            Button(isOn ? "Don't Clean" : "Clean This Area") { model.toggle(category) }
            Button("Show Items") { model.showDetails(for: category) }
        }
        Divider()
        Button("Show in Finder") {
            let existing = category.roots.filter { FileManager.default.fileExists(atPath: $0.path) }
            NSWorkspace.shared.activateFileViewerSelecting(existing)
        }
    }

    private var caption: String {
        if isScanning { return "Looking for junk…" }
        if locked { return "Click to grant Full Disk Access" }
        return itemCount == 0 ? "Already clean" : "\(itemCount) item\(itemCount == 1 ? "" : "s")"
    }

    private var accessibilityValue: String {
        if isScanning { return "Scanning" }
        if locked { return "Locked, needs Full Disk Access" }
        return "\(Format.bytes(model.size(of: category))), \(isOn ? "selected" : "not selected")"
    }
}
