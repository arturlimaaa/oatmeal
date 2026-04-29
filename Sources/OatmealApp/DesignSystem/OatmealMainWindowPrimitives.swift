import OatmealCore
import SwiftUI

// MARK: - CitationPill

/// A compact chip that links a spoken moment back to the transcript. Used
/// beneath AI answers, inside note callouts, and anywhere else a claim needs
/// to point at evidence. Format: `[●][speaker name][mono timestamp]`.
///
/// The leading dot uses the speaker's palette slot from
/// `OatmealSpeakerColor`, so the same speaker always reads in the same hue
/// across transcript, notes, summary, and citations.
public struct CitationPill: View {
    public enum Style {
        /// Summary-page pill: `[● dot][speaker][mono time]` on a card fill.
        case summary
        /// Workspace chat pill: `[mono time][speaker]` on a paper2 fill,
        /// no leading dot. Designed to sit under an assistant bubble.
        case workspace
    }

    public var speakerName: String
    public var timestamp: String
    public var style: Style
    public var action: (() -> Void)?

    public init(
        speakerName: String,
        timestamp: String,
        style: Style = .summary,
        action: (() -> Void)? = nil
    ) {
        self.speakerName = speakerName
        self.timestamp = timestamp
        self.style = style
        self.action = action
    }

    public var body: some View {
        if let action {
            Button(action: action) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
    }

    private var content: some View {
        HStack(spacing: 6) {
            switch style {
            case .summary:
                Circle()
                    .fill(OatmealSpeakerColor.color(for: speakerName))
                    .frame(width: 6, height: 6)
                Text(speakerName)
                    .font(.om.caption)
                    .foregroundStyle(Color.om.ink2)
                Text(timestamp)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
            case .workspace:
                Text(timestamp)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                Text(speakerName)
                    .font(.om.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(OatmealSpeakerColor.color(for: speakerName))
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(style == .workspace ? Color.om.paper2 : Color.om.card)
        .overlay(
            Capsule()
                .strokeBorder(Color.om.line, lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

// MARK: - ActionItemRow

/// A single action-item line shared between the inline notes card and the
/// summary right-rail card. Status is a small symbol on the left; the status
/// pill on the right mirrors it so the row scans in either direction.
public struct ActionItemRow: View {
    public var item: ActionItem

    public init(item: ActionItem) { self.item = item }

    public var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: statusSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(statusColor)
                .frame(width: 16, alignment: .leading)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.text)
                    .font(.om.body)
                    .foregroundStyle(Color.om.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if meta.isEmpty == false {
                    Text(meta)
                        .font(.om.caption)
                        .foregroundStyle(Color.om.ink3)
                }
            }

            Spacer(minLength: 8)

            Text(statusLabel)
                .font(.om.caption)
                .fontWeight(.semibold)
                .foregroundStyle(statusColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(statusColor.opacity(0.12), in: Capsule())
        }
        .padding(.vertical, 10)
    }

    private var meta: String {
        var parts: [String] = []
        if let assignee = item.assignee, !assignee.isEmpty {
            parts.append(assignee)
        }
        if let due = item.dueDate {
            parts.append(due.formatted(date: .abbreviated, time: .omitted))
        }
        if parts.isEmpty {
            parts.append("No owner yet")
        }
        return parts.joined(separator: " · ")
    }

    private var statusSymbol: String {
        switch item.status {
        case .open:      return "circle"
        case .delegated: return "arrow.turn.up.right"
        case .done:      return "checkmark.circle.fill"
        }
    }

    private var statusLabel: String {
        switch item.status {
        case .open:      return "Open"
        case .delegated: return "Delegated"
        case .done:      return "Done"
        }
    }

    private var statusColor: Color {
        switch item.status {
        case .open:      return Color.om.oat2
        case .delegated: return Color.om.ring
        case .done:      return Color.om.sage2
        }
    }
}

// MARK: - MeetingRow

/// Library row used under day-group eyebrows. Four columns:
/// `[mono start time] [serif title + people line + optional LIVE pill] [tag chip] [mono duration]`.
///
/// The row is deliberately flat — no card, no border by default. The selected
/// state gets a faint `card` wash so the row still feels like it belongs to
/// the list rather than snapping out of it.
public struct MeetingRow: View {
    public var startDate: Date
    public var endDate: Date?
    public var title: String
    public var peopleLine: String?
    public var tag: String?
    public var isLive: Bool
    public var isSelected: Bool
    public var action: () -> Void

    @State private var isHovered = false

    public init(
        startDate: Date,
        endDate: Date? = nil,
        title: String,
        peopleLine: String? = nil,
        tag: String? = nil,
        isLive: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.peopleLine = peopleLine
        self.tag = tag
        self.isLive = isLive
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 16) {
                Text(timeLabel)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                    .frame(width: 60, alignment: .leading)
                    .padding(.top, 3)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(title)
                            .font(.om.rowTitle)
                            .foregroundStyle(Color.om.ink)
                            .lineLimit(1)
                        if isLive {
                            LivePill()
                        }
                    }
                    if let peopleLine, !peopleLine.isEmpty {
                        Text(peopleLine)
                            .font(.om.caption)
                            .foregroundStyle(Color.om.ink3)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 12)

                if let tag, !tag.isEmpty {
                    Text(tag)
                        .font(.om.meta)
                        .foregroundStyle(Color.om.ink2)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.om.paper3, in: RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 2)
                }

                Text(durationLabel)
                    .font(.om.meta)
                    .foregroundStyle(Color.om.ink3)
                    .frame(width: 44, alignment: .trailing)
                    .padding(.top, 3)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(rowBackground)
            .clipShape(RoundedRectangle(cornerRadius: OMRadius.sm))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var rowBackground: Color {
        if isSelected { return Color.om.card }
        if isHovered { return Color.om.ring.opacity(0.06) }
        return Color.clear
    }

    private var timeLabel: String {
        startDate.formatted(Date.FormatStyle().hour().minute())
    }

    private var durationLabel: String {
        guard let endDate else { return "—" }
        let minutes = max(0, Int(endDate.timeIntervalSince(startDate) / 60.0))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)"
    }
}

// MARK: - MeetingCard

/// Grid alternative to `MeetingRow`. Same data, displayed as a small card —
/// title up top, optional people line, footer with start time, duration, and
/// optional tag chip.
public struct MeetingCard: View {
    public var startDate: Date
    public var endDate: Date?
    public var title: String
    public var peopleLine: String?
    public var tag: String?
    public var isLive: Bool
    public var isSelected: Bool
    public var action: () -> Void

    @State private var isHovered = false

    public init(
        startDate: Date,
        endDate: Date? = nil,
        title: String,
        peopleLine: String? = nil,
        tag: String? = nil,
        isLive: Bool = false,
        isSelected: Bool = false,
        action: @escaping () -> Void
    ) {
        self.startDate = startDate
        self.endDate = endDate
        self.title = title
        self.peopleLine = peopleLine
        self.tag = tag
        self.isLive = isLive
        self.isSelected = isSelected
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(title)
                        .font(.om.rowTitle)
                        .foregroundStyle(Color.om.ink)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 4)
                    if isLive {
                        LivePill()
                    }
                }

                if let peopleLine, !peopleLine.isEmpty {
                    Text(peopleLine)
                        .font(.om.caption)
                        .foregroundStyle(Color.om.ink3)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    Text(timeLabel)
                        .font(.om.meta)
                        .foregroundStyle(Color.om.ink3)
                    Text("·")
                        .font(.om.meta)
                        .foregroundStyle(Color.om.ink4)
                    Text(durationLabel)
                        .font(.om.meta)
                        .foregroundStyle(Color.om.ink3)
                    Spacer(minLength: 0)
                    if let tag, !tag.isEmpty {
                        Text(tag)
                            .font(.om.meta)
                            .foregroundStyle(Color.om.ink2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.om.paper3, in: RoundedRectangle(cornerRadius: 4))
                    }
                }
            }
            .padding(14)
            .frame(height: 124, alignment: .topLeading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: OMRadius.md)
                    .strokeBorder(isSelected ? Color.om.ink.opacity(0.25) : Color.om.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: OMRadius.md))
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
    }

    private var cardBackground: Color {
        if isSelected { return Color.om.card }
        if isHovered { return Color.om.ring.opacity(0.06) }
        return Color.om.paper2
    }

    private var timeLabel: String {
        startDate.formatted(Date.FormatStyle().hour().minute())
    }

    private var durationLabel: String {
        guard let endDate else { return "—" }
        let minutes = max(0, Int(endDate.timeIntervalSince(startDate) / 60.0))
        if minutes < 60 {
            return "\(minutes)m"
        }
        let hours = minutes / 60
        let remainder = minutes % 60
        return remainder == 0 ? "\(hours)h" : "\(hours)h\(remainder)"
    }
}

private struct LivePill: View {
    var body: some View {
        HStack(spacing: 4) {
            OMRecDot(size: 6)
            Text("LIVE")
                .font(.om.meta)
                .fontWeight(.bold)
                .tracking(0.8)
                .foregroundStyle(Color.om.recDot)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(Color.om.recDot.opacity(0.10), in: Capsule())
    }
}

// MARK: - Previews

#Preview("MainWindow primitives") {
    VStack(alignment: .leading, spacing: 18) {
        HStack(spacing: 8) {
            CitationPill(speakerName: "Priya Shah", timestamp: "12:04")
            CitationPill(speakerName: "Jordan Lee", timestamp: "14:22")
            CitationPill(speakerName: "Ana Ruiz", timestamp: "22:08")
        }
        OMHairline()
        VStack(spacing: 0) {
            ActionItemRow(item: ActionItem(text: "Draft the launch post for Tuesday morning", assignee: "Priya", status: .open))
            OMHairline()
            ActionItemRow(item: ActionItem(text: "Send Ana the updated pricing deck", status: .done))
        }
        OMHairline()
        VStack(spacing: 2) {
            MeetingRow(
                startDate: .now,
                endDate: .now.addingTimeInterval(45 * 60),
                title: "Design review · onboarding",
                peopleLine: "Priya, Jordan, Ana",
                tag: "Design",
                isLive: true,
                isSelected: true,
                action: {}
            )
            MeetingRow(
                startDate: .now.addingTimeInterval(-3_600),
                endDate: .now.addingTimeInterval(-3_000),
                title: "1:1 · Priya",
                peopleLine: "Priya",
                tag: "1:1",
                action: {}
            )
        }
    }
    .padding(24)
    .frame(width: 640)
    .background(Color.om.paper)
}
