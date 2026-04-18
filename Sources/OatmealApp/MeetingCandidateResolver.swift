import Foundation
import OatmealCore

@MainActor
protocol MeetingCandidateResolving {
    func resolve(
        detection: PendingMeetingDetection,
        availableEvents: [CalendarEvent]
    ) -> PendingMeetingDetection
}

@MainActor
struct LiveMeetingCandidateResolver: MeetingCandidateResolving {
    private let maximumStartLeadTime: TimeInterval
    private let maximumEndLagTime: TimeInterval
    private let ambiguousScoreGap: Double

    init(
        maximumStartLeadTime: TimeInterval = 20 * 60,
        maximumEndLagTime: TimeInterval = 10 * 60,
        ambiguousScoreGap: Double = 18
    ) {
        self.maximumStartLeadTime = maximumStartLeadTime
        self.maximumEndLagTime = maximumEndLagTime
        self.ambiguousScoreGap = ambiguousScoreGap
    }

    func resolve(
        detection: PendingMeetingDetection,
        availableEvents: [CalendarEvent]
    ) -> PendingMeetingDetection {
        guard detection.calendarEvent == nil, detection.candidateCalendarEvents.isEmpty else {
            return detection
        }

        let scoredCandidates = availableEvents
            .filter { isCandidateWindowMatch($0, detectedAt: detection.detectedAt) }
            .map { event in
                ScoredMeetingCandidate(
                    event: event,
                    score: score(event: event, for: detection)
                )
            }
            .filter { $0.score > 0 }
            .sorted(by: ScoredMeetingCandidate.preferredOrder)

        guard let topCandidate = scoredCandidates.first else {
            return detection
        }

        var resolvedDetection = detection
        if scoredCandidates.count == 1 {
            resolvedDetection.calendarEvent = topCandidate.event
            return resolvedDetection
        }

        let secondCandidate = scoredCandidates[1]
        if topCandidate.score - secondCandidate.score >= ambiguousScoreGap {
            resolvedDetection.calendarEvent = topCandidate.event
            return resolvedDetection
        }

        resolvedDetection.candidateCalendarEvents = scoredCandidates.map(\.event)
        resolvedDetection.calendarEvent = nil
        return resolvedDetection
    }

    private func isCandidateWindowMatch(_ event: CalendarEvent, detectedAt: Date) -> Bool {
        guard event.isRelevantForHomeScreen else {
            return false
        }

        let startsSoonEnough = event.startDate <= detectedAt.addingTimeInterval(maximumStartLeadTime)
        let endedRecentlyEnough = event.endDate >= detectedAt.addingTimeInterval(-maximumEndLagTime)
        return startsSoonEnough && endedRecentlyEnough
    }

    private func score(event: CalendarEvent, for detection: PendingMeetingDetection) -> Double {
        var score = 0.0
        let detectedAt = detection.detectedAt

        if event.startDate <= detectedAt, event.endDate >= detectedAt {
            score += 120
        }

        let startDistanceMinutes = abs(event.startDate.timeIntervalSince(detectedAt)) / 60
        score += max(0, 45 - startDistanceMinutes * 3)

        if event.conferencingURL != nil {
            score += 12
        }

        if event.attendanceStatus == .accepted {
            score += 5
        }

        if event.kind == .meeting {
            score += 4
        }

        if eventSourceLikelyMatchesDetection(event: event, detection: detection) {
            score += 24
        }

        return score
    }

    private func eventSourceLikelyMatchesDetection(
        event: CalendarEvent,
        detection: PendingMeetingDetection
    ) -> Bool {
        guard detection.source.kind == .nativeApp else {
            return false
        }

        let normalizedSource = detection.source.displayName.lowercased()
        let haystacks = [
            event.title,
            event.location,
            event.notes,
            event.conferencingURL?.absoluteString
        ]
            .compactMap { $0?.lowercased() }

        return haystacks.contains(where: { $0.contains(normalizedSource) })
    }
}

private struct ScoredMeetingCandidate {
    let event: CalendarEvent
    let score: Double

    static func preferredOrder(lhs: Self, rhs: Self) -> Bool {
        if lhs.score != rhs.score {
            return lhs.score > rhs.score
        }

        if lhs.event.startDate != rhs.event.startDate {
            return lhs.event.startDate < rhs.event.startDate
        }

        return lhs.event.title.localizedCaseInsensitiveCompare(rhs.event.title) == .orderedAscending
    }
}
