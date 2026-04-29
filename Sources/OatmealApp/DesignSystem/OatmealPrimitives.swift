import SwiftUI

// MARK: - OMEyebrow

/// Small mono uppercase label. Used above titles, as section markers, and as
/// quiet metadata captions.
public struct OMEyebrow: View {
    public var text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text.uppercased())
            .font(.om.eyebrow)
            .tracking(1.8)
            .foregroundStyle(Color.om.ink3)
            .accessibilityAddTraits(.isHeader)
    }
}

// MARK: - OMKbd

/// Keystroke pill (`⌘K`, `⌘⇧9`). Mono, soft card background, tiny shadow line
/// at the bottom so it reads as a key rather than as text.
public struct OMKbd: View {
    public var text: String

    public init(_ text: String) { self.text = text }

    public var body: some View {
        Text(text)
            .font(.om.kbd)
            .foregroundStyle(Color.om.ink3)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.om.card)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Color.om.line2, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - OMHairline

/// A single-pixel divider in the hairline color. Use for section separators,
/// sidebar edges, and sub-toolbar borders.
public struct OMHairline: View {
    public enum Axis { case horizontal, vertical }
    public var axis: Axis

    public init(_ axis: Axis = .horizontal) { self.axis = axis }

    public var body: some View {
        switch axis {
        case .horizontal:
            Color.om.line.frame(height: 1)
        case .vertical:
            Color.om.line.frame(width: 1)
        }
    }
}

// MARK: - OMCard

/// A soft card container: card-colored background, hairline border, medium radius.
public struct OMCard<Content: View>: View {
    public var padding: CGFloat
    public var content: Content

    public init(padding: CGFloat = OMSpacing.s4, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(Color.om.card)
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(Color.om.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
    }
}

// MARK: - OMButton

/// Variant for `OMButton`. Primary is ink-on-paper (dark inverted button),
/// secondary is card-on-paper with a hairline border.
public enum OMButtonVariant {
    case primary
    case secondary
    case destructive
}

/// Oatmeal button. Wraps a native `Button` with a `ButtonStyle` so keyboard
/// focus and accessibility still work.
public struct OMButton<Label: View>: View {
    public var variant: OMButtonVariant
    public var action: () -> Void
    public var label: () -> Label

    public init(
        variant: OMButtonVariant = .secondary,
        action: @escaping () -> Void,
        @ViewBuilder label: @escaping () -> Label
    ) {
        self.variant = variant
        self.action = action
        self.label = label
    }

    public var body: some View {
        Button(action: action, label: label)
            .buttonStyle(OMButtonStyle(variant: variant))
    }
}

public extension OMButton where Label == Text {
    init(_ title: String, variant: OMButtonVariant = .secondary, action: @escaping () -> Void) {
        self.variant = variant
        self.action = action
        self.label = { Text(title) }
    }
}

private struct OMButtonStyle: ButtonStyle {
    var variant: OMButtonVariant

    func makeBody(configuration: Configuration) -> some View {
        let palette = stylePalette(for: variant, pressed: configuration.isPressed)
        return configuration.label
            .font(.om.button)
            .foregroundStyle(palette.fg)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(palette.bg)
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(palette.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(RoundedRectangle(cornerRadius: 7))
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private struct StylePalette { let fg: Color; let bg: Color; let border: Color }

    private func stylePalette(for variant: OMButtonVariant, pressed: Bool) -> StylePalette {
        switch variant {
        case .primary:
            return StylePalette(
                fg: Color.om.paper,
                bg: pressed ? Color.om.ink2 : Color.om.ink,
                border: Color.om.ink
            )
        case .secondary:
            return StylePalette(
                fg: Color.om.ink,
                bg: pressed ? Color.om.paper2 : Color.om.card,
                border: Color.om.line2
            )
        case .destructive:
            return StylePalette(
                fg: Color.om.ember,
                bg: pressed
                    ? Color.om.ember.opacity(0.16)
                    : Color.om.ember.opacity(0.08),
                border: Color.om.ember.opacity(0.3)
            )
        }
    }
}

// MARK: - OMRecDot

/// The recording indicator — a red dot with an expanding pulse ring.
/// Respects `Reduce Motion` by disabling the pulse animation when the user
/// has that accessibility setting enabled.
public struct OMRecDot: View {
    public var size: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulse = false

    public init(size: CGFloat = 8) { self.size = size }

    public var body: some View {
        Circle()
            .fill(Color.om.recDot)
            .frame(width: size, height: size)
            .overlay(
                Circle()
                    .stroke(Color.om.recDot.opacity(0.55), lineWidth: 2)
                    .scaleEffect(pulse ? 2.4 : 1.0)
                    .opacity(pulse ? 0 : 1)
                    .animation(
                        reduceMotion
                            ? nil
                            : .easeOut(duration: 1.6).repeatForever(autoreverses: false),
                        value: pulse
                    )
            )
            .onAppear { if !reduceMotion { pulse = true } }
            .accessibilityLabel("Recording")
    }
}

// MARK: - OMWaveform

/// Six-bar animated waveform used wherever we signal "live audio in / live
/// transcript in progress." Respects Reduce Motion.
public struct OMWaveform: View {
    public var barCount: Int
    public var tint: Color

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: Double = 0

    public init(barCount: Int = 6, tint: Color = Color.om.ink2) {
        self.barCount = barCount
        self.tint = tint
    }

    public var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<barCount, id: \.self) { i in
                    let offset = Double(i) * 0.22
                    let h = reduceMotion
                        ? 7.0
                        : 3.0 + (sin(t * 3.5 - offset) + 1.0) * 4.5
                    Capsule()
                        .fill(tint)
                        .frame(width: 2, height: h)
                }
            }
            .frame(height: 14)
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Previews

#Preview("OatmealPrimitives") {
    VStack(alignment: .leading, spacing: 18) {
        OMEyebrow("Library · Today")
        HStack(spacing: 8) {
            OMButton("Summarize", variant: .secondary) {}
            OMButton("New meeting", variant: .primary) {}
            OMButton("Stop & save", variant: .destructive) {}
            OMKbd("⌘⇧9")
        }
        OMCard {
            VStack(alignment: .leading, spacing: 8) {
                OMEyebrow("Decisions · 2")
                Text("Local Whisper becomes default under 30 minutes.")
                    .font(.om.bodyParagraph)
                    .foregroundStyle(Color.om.ink2)
            }
        }
        HStack(spacing: 12) {
            OMRecDot()
            OMWaveform()
            Text("Recording…")
                .font(.om.body)
                .foregroundStyle(Color.om.ink3)
        }
        OMHairline()
    }
    .padding(24)
    .frame(width: 420)
    .background(Color.om.paper)
}
