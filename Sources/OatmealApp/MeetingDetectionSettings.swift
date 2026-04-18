import Foundation

struct MeetingDetectionConfiguration: Codable, Equatable, Sendable {
    var zoomEnabled: Bool
    var teamsEnabled: Bool
    var slackEnabled: Bool
    var browsersEnabled: Bool
    var highConfidenceAutoStartEnabled: Bool

    init(
        zoomEnabled: Bool = true,
        teamsEnabled: Bool = true,
        slackEnabled: Bool = true,
        browsersEnabled: Bool = true,
        highConfidenceAutoStartEnabled: Bool = false
    ) {
        self.zoomEnabled = zoomEnabled
        self.teamsEnabled = teamsEnabled
        self.slackEnabled = slackEnabled
        self.browsersEnabled = browsersEnabled
        self.highConfidenceAutoStartEnabled = highConfidenceAutoStartEnabled
    }

    static let `default` = MeetingDetectionConfiguration()

    func isEnabled(for source: PendingMeetingDetection.Source) -> Bool {
        switch source.kind {
        case .browser:
            return browsersEnabled
        case .nativeApp:
            switch MeetingDetectionSourceSetting.matching(sourceDisplayName: source.displayName) {
            case .zoom:
                return zoomEnabled
            case .teams:
                return teamsEnabled
            case .slack:
                return slackEnabled
            case .browsers:
                return false
            }
        case .unknown:
            return true
        }
    }
}

enum MeetingDetectionSourceSetting: String, CaseIterable, Codable, Equatable, Sendable, Identifiable {
    case zoom
    case teams
    case slack
    case browsers

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .zoom:
            return "Zoom"
        case .teams:
            return "Teams"
        case .slack:
            return "Slack"
        case .browsers:
            return "Browsers"
        }
    }

    static func matching(sourceDisplayName: String) -> Self {
        let normalized = sourceDisplayName
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        if normalized.contains("zoom") {
            return .zoom
        }

        if normalized.contains("teams") {
            return .teams
        }

        if normalized.contains("slack") {
            return .slack
        }

        return .browsers
    }
}
