import SwiftUI

// Liquid Glass helpers: real glass on macOS 26+, system materials on macOS 14/15.
// Per the Liquid Glass guidance, these are always applied *after* layout modifiers,
// `interactive` is only used on elements that respond to input, and grouped glass
// lives inside a `GlassGroup` (GlassEffectContainer) whose spacing matches the layout.

extension View {
    /// Rounded-rectangle glass surface (cards).
    @ViewBuilder
    func glassCard(cornerRadius: CGFloat = 22, tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: .rect(cornerRadius: cornerRadius))
        } else {
            background {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius).fill(tint ?? .clear))
            }
            .overlay(RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(.white.opacity(0.18)))
        }
    }

    /// Capsule glass (pills, chips).
    @ViewBuilder
    func glassCapsule(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: .capsule)
        } else {
            background(Capsule().fill(tint ?? .clear).background(.ultraThinMaterial, in: Capsule()))
                .overlay(Capsule().strokeBorder(.white.opacity(0.2)))
        }
    }

    /// Circular glass (icon buttons).
    @ViewBuilder
    func glassCircle(tint: Color? = nil, interactive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular.tint(tint).interactive(interactive), in: .circle)
        } else {
            background(Circle().fill(tint ?? .clear).background(.ultraThinMaterial, in: Circle()))
                .overlay(Circle().strokeBorder(.white.opacity(0.2)))
        }
    }

    /// Identity used to morph glass shapes between view-hierarchy changes.
    @ViewBuilder
    func glassMorphID(_ id: String, in namespace: Namespace.ID) -> some View {
        if #available(macOS 26.0, *) {
            glassEffectID(id, in: namespace)
        } else {
            self
        }
    }
}

extension View {
    /// macOS 26: a crisp (not see-through) edge under the toolbar, so scrolled
    /// content doesn't show through the title bar.
    @ViewBuilder
    func hardTopScrollEdge() -> some View {
        if #available(macOS 26.0, *) {
            scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            self
        }
    }
}

/// Capsule action button with Liquid Glass that can morph inside a `GlassGroup`.
///
/// On macOS 26+ it uses the system `.glass` / `.glassProminent` button styles. Don't build
/// these as a plain Button whose label carries `.glassEffect(.interactive())` + `glassEffectID`
/// inside a GlassEffectContainer: that glass swallows the click and the action never fires.
struct GlassPillButton<Label: View>: View {
    /// A tint makes it the prominent (filled) style.
    var tint: Color? = nil
    var morphID: String
    var namespace: Namespace.ID
    var action: () -> Void
    @ViewBuilder var label: Label

    var body: some View {
        if #available(macOS 26.0, *) {
            styled(Button(action: action) {
                label
                    .lineLimit(1)
                    .padding(.horizontal, 6)
                    .frame(minHeight: 22)
            })
            .controlSize(.large)
            .buttonBorderShape(.capsule)
            .glassEffectID(morphID, in: namespace)
        } else {
            Button(action: action) {
                label
                    .foregroundStyle(tint == nil ? Color.primary : Color.white)
                    .pill()
                    .glassCapsule(tint: tint)
            }
            .buttonStyle(.plain)
        }
    }

    @available(macOS 26.0, *)
    @ViewBuilder
    private func styled<B: View>(_ button: B) -> some View {
        if let tint {
            button.buttonStyle(.glassProminent).tint(tint)
        } else {
            button.buttonStyle(.glass)
        }
    }
}

/// Wraps grouped glass so it shares one sampling region and can blend/morph.
struct GlassGroup<Content: View>: View {
    var spacing: CGFloat
    @ViewBuilder var content: Content

    var body: some View {
        if #available(macOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { content }
        } else {
            content
        }
    }
}

/// Soft color field that gives the glass something to refract.
/// Deliberately static: an animated background forces every glass surface
/// above it to re-render each frame, which makes resizing and the inspector laggy.
struct AuroraBackground: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if #available(macOS 15.0, *) {
            MeshGradient(
                width: 3, height: 3,
                points: [
                    [0, 0], [0.55, 0], [1, 0],
                    [0, 0.45], [0.6, 0.55], [1, 0.4],
                    [0, 1], [0.45, 1], [1, 1],
                ],
                colors: palette)
        } else {
            LinearGradient(colors: [palette[0], palette[4], palette[8]],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
        }
    }

    private var palette: [Color] {
        func rgb(_ r: Double, _ g: Double, _ b: Double) -> Color { Color(red: r, green: g, blue: b) }
        if scheme == .dark {
            return [rgb(0.09, 0.07, 0.26), rgb(0.24, 0.09, 0.40), rgb(0.05, 0.16, 0.38),
                    rgb(0.04, 0.26, 0.40), rgb(0.30, 0.10, 0.48), rgb(0.46, 0.10, 0.36),
                    rgb(0.05, 0.07, 0.22), rgb(0.09, 0.19, 0.48), rgb(0.26, 0.07, 0.35)]
        }
        return [rgb(0.84, 0.89, 1.00), rgb(0.93, 0.86, 1.00), rgb(0.82, 0.94, 1.00),
                rgb(0.80, 0.96, 0.97), rgb(0.96, 0.88, 0.99), rgb(1.00, 0.87, 0.92),
                rgb(0.86, 0.90, 1.00), rgb(0.84, 0.92, 1.00), rgb(0.94, 0.87, 1.00)]
    }
}

extension CleanCategory {
    var tint: Color {
        switch id {
        case "trash": .pink
        case "userCaches": .blue
        case "userLogs": .orange
        case "xcode": .cyan
        case "devCaches": .green
        case "temp": .yellow
        case "systemCaches": .purple
        default: .indigo
        }
    }
}
