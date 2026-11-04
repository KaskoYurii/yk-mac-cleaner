import SwiftUI

/// Summary at the top: a progress ring, headline, and a morphing group of glass actions.
/// The hero itself is plain content (not glass) so the glass controls never sit on glass.
struct HeroView: View {
    let model: CleanerModel

    var body: some View {
        HStack(spacing: 28) {
            ViewThatFits(in: .horizontal) {
                ring(size: 156)
                ring(size: 112)
            }
            .frame(maxWidth: 156)
            text(alignment: .leading)
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func ring(size: CGFloat) -> some View {
        JunkRing(fraction: ringFraction, value: ringValue, caption: ringCaption,
                 done: phase == .finished, size: size)
    }

    private func text(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(title)
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .contentTransition(.numericText())
            Text(subtitle)
                .font(.title3)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .fixedSize(horizontal: false, vertical: true)
            HeroActions(model: model, phase: phase)
                .padding(.top, 12)
        }
        .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
        .animation(.smooth(duration: 0.35), value: title)
    }

    // MARK: State

    enum Phase: Equatable { case scanning, cleaning, finished, ready, nothingSelected }

    private var phase: Phase {
        if model.isCleaning { return .cleaning }
        if model.isScanning && model.finishedReport == nil { return .scanning }
        if model.finishedReport != nil { return .finished }
        return model.selectedTotal > 0 ? .ready : .nothingSelected
    }

    private var ringFraction: Double {
        switch phase {
        case .scanning:
            let total = Double(model.categories.count)
            return total == 0 ? 0 : (total - Double(model.scanning.count)) / total
        case .cleaning, .finished: return 1
        case .ready, .nothingSelected:
            let grand = Double(model.grandTotal)
            return grand == 0 ? 1 : Double(model.selectedTotal) / grand
        }
    }

    private var ringValue: String {
        switch phase {
        case .scanning: "\(model.categories.count - model.scanning.count)/\(model.categories.count)"
        case .finished: Format.bytes(model.finishedReport?.freed ?? 0)
        default: Format.bytes(model.selectedTotal)
        }
    }

    private var ringCaption: String {
        switch phase {
        case .scanning: "areas checked"
        case .cleaning: "cleaning"
        case .finished: "freed"
        default: "selected"
        }
    }

    private var title: String {
        switch phase {
        case .scanning: "Scanning your Mac…"
        case .cleaning: "Cleaning up…"
        case .finished: "Freed \(Format.bytes(model.finishedReport?.freed ?? 0))"
        case .ready: "\(Format.bytes(model.selectedTotal)) ready to clean"
        case .nothingSelected: model.grandTotal == 0 ? "Your Mac is spotless" : "Nothing selected"
        }
    }

    private var subtitle: String {
        switch phase {
        case .scanning: return "Checking caches, logs, Trash and developer leftovers."
        case .cleaning: return "Removing the selected files. This only takes a moment."
        case .finished:
            guard let r = model.finishedReport else { return "" }
            var parts = ["Removed \(r.removed) item\(r.removed == 1 ? "" : "s")."]
            if !r.failed.isEmpty { parts.append("\(r.failed.count) in use or protected by macOS.") }
            if r.adminCancelled { parts.append("System items skipped.") }
            return parts.joined(separator: " ")
        case .ready:
            let n = model.selected.count
            return "\(Format.bytes(model.grandTotal)) found in total · \(n) area\(n == 1 ? "" : "s") selected"
        case .nothingSelected:
            return model.grandTotal == 0 ? "No junk found. Check back later." : "Choose the areas below that you want to clean."
        }
    }
}

/// Glass action pills that morph between phases (same container + namespace + glassEffectID).
private struct HeroActions: View {
    let model: CleanerModel
    let phase: HeroView.Phase
    @Namespace private var glass
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let spacing: CGFloat = 10

    var body: some View {
        GlassGroup(spacing: spacing) {
            HStack(spacing: spacing) {
                switch phase {
                case .scanning, .cleaning:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(phase == .scanning ? "Scanning" : "Cleaning")
                            .fontWeight(.medium)
                    }
                    .pill()
                    .glassCapsule()
                    .glassMorphID("primary", in: glass)
                    .accessibilityElement(children: .combine)

                case .ready:
                    GlassPillButton(tint: .accentColor, morphID: "primary", namespace: glass,
                                    action: model.requestClean) {
                        Label("Clean \(Format.bytes(model.selectedTotal))", systemImage: "sparkles")
                            .fontWeight(.semibold)
                    }
                    .help("Clean the selected areas (⌘⌫)")

                    GlassPillButton(morphID: "secondary", namespace: glass) {
                        if let first = model.categories.first(where: { model.selected.contains($0.id) }) {
                            model.showDetails(for: first)
                        }
                    } label: {
                        Label("Review", systemImage: "eye")
                            .fontWeight(.medium)
                    }
                    .help("See which files will be removed (⌥⌘I)")

                case .finished:
                    GlassPillButton(tint: .green, morphID: "primary", namespace: glass) {
                        model.finishedReport = nil
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .fontWeight(.semibold)
                    }
                    .keyboardShortcut(.defaultAction)

                case .nothingSelected:
                    if model.grandTotal > 0 {
                        GlassPillButton(morphID: "primary", namespace: glass, action: model.selectAll) {
                            Label("Select All", systemImage: "checklist")
                                .fontWeight(.semibold)
                        }
                    } else {
                        GlassPillButton(morphID: "primary", namespace: glass) {
                            Task { await model.scan() }
                        } label: {
                            Label("Scan Again", systemImage: "arrow.clockwise")
                                .fontWeight(.semibold)
                        }
                    }
                }
            }
        }
        .animation(reduceMotion ? nil : .bouncy(duration: 0.5), value: phase)
    }
}

extension View {
    func pill() -> some View {
        lineLimit(1)
            .padding(.horizontal, 18)
            .frame(height: 36)
            .contentShape(Capsule())
    }
}

struct JunkRing: View {
    var fraction: Double
    var value: String
    var caption: String
    var done: Bool
    var size: CGFloat = 156

    private var lineWidth: CGFloat { size > 130 ? 14 : 11 }

    var body: some View {
        ZStack {
            Circle()
                .stroke(.primary.opacity(0.08), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, fraction))
                .stroke(
                    done
                        ? AngularGradient(colors: [.mint, .green, .teal, .mint], center: .center)
                        : AngularGradient(colors: [.cyan, .blue, .purple, .pink, .cyan], center: .center),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .shadow(color: (done ? Color.green : .purple).opacity(0.35), radius: 10)
            VStack(spacing: 2) {
                Text(value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .contentTransition(.numericText())
                Text(caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(size > 130 ? 24 : 18)
        }
        .frame(width: size, height: size)
        .animation(.smooth(duration: 0.6), value: fraction)
        .animation(.smooth(duration: 0.4), value: done)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(value) \(caption)")
    }
}
