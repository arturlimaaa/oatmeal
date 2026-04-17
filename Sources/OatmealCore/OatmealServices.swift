import Foundation

public enum ShareError: Error, Equatable, Sendable {
    case privateNoteCannotBeShared
    case noteNotFound
    case linkNotFound
}

public protocol CalendarEventProviding {
    func upcomingMeetings(referenceDate: Date, horizon: TimeInterval) -> [CalendarEvent]
}

public protocol MeetingNoteRepository {
    func note(id: UUID) -> MeetingNote?
    func allNotes() -> [MeetingNote]
    func save(_ note: MeetingNote)
    func delete(noteID: UUID)
    func move(noteID: UUID, to folderID: UUID?)
    func search(query: String, filters: NoteSearchFilters) -> [NoteSearchResult]
}

public protocol TemplateProviding {
    func template(id: UUID) -> NoteTemplate?
    func allTemplates() -> [NoteTemplate]
    var defaultTemplate: NoteTemplate { get }
}

public protocol NoteGenerationService {
    func generate(from request: NoteGenerationRequest) throws -> EnhancedNote
}

public protocol NoteSharingService {
    func createShareLink(for note: MeetingNote, baseURL: URL) throws -> SharedNoteLink
    func revokeShareLink(linkID: UUID)
    func shareLink(id: UUID) -> SharedNoteLink?
}

public final class InMemoryOatmealStore: CalendarEventProviding, MeetingNoteRepository, TemplateProviding, NoteSharingService {
    private var events: [CalendarEvent]
    private var notesByID: [UUID: MeetingNote]
    private var foldersByID: [UUID: NoteFolder]
    private var templatesByID: [UUID: NoteTemplate]
    private var shareLinksByID: [UUID: SharedNoteLink]
    private var defaultTemplateID: UUID

    public init(
        events: [CalendarEvent] = [],
        notes: [MeetingNote] = [],
        folders: [NoteFolder] = [],
        templates: [NoteTemplate] = NoteTemplate.builtInTemplates,
        defaultTemplateID: UUID? = nil,
        shareLinks: [SharedNoteLink] = []
    ) {
        self.events = events
        self.notesByID = Dictionary(uniqueKeysWithValues: notes.map { ($0.id, $0) })
        self.foldersByID = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0) })
        self.templatesByID = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
        self.shareLinksByID = Dictionary(uniqueKeysWithValues: shareLinks.map { ($0.id, $0) })
        self.defaultTemplateID = defaultTemplateID ?? templates.first(where: { $0.isDefault })?.id ?? templates.first?.id ?? UUID()
    }

    public static func preview(referenceDate: Date = Date()) -> InMemoryOatmealStore {
        OatmealSeedData.preview(referenceDate: referenceDate)
    }

    public var folders: [NoteFolder] {
        foldersByID.values.sorted { $0.createdAt < $1.createdAt }
    }

    public func folder(id: UUID) -> NoteFolder? {
        foldersByID[id]
    }

    public func upcomingMeetings(referenceDate: Date, horizon: TimeInterval) -> [CalendarEvent] {
        let endDate = referenceDate.addingTimeInterval(horizon)
        return events
            .filter { $0.isRelevantForHomeScreen && $0.startDate >= referenceDate && $0.startDate <= endDate }
            .sorted { $0.startDate < $1.startDate }
    }

    public func note(id: UUID) -> MeetingNote? {
        notesByID[id]
    }

    public func allNotes() -> [MeetingNote] {
        notesByID.values.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func save(_ note: MeetingNote) {
        notesByID[note.id] = note
    }

    public func delete(noteID: UUID) {
        notesByID[noteID] = nil
        shareLinksByID = shareLinksByID.filter { $0.value.noteID != noteID }
    }

    public func move(noteID: UUID, to folderID: UUID?) {
        guard var note = notesByID[noteID] else { return }
        note.assignFolder(folderID)
        notesByID[noteID] = note
    }

    public func search(query: String, filters: NoteSearchFilters = NoteSearchFilters()) -> [NoteSearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else {
            return []
        }

        return allNotes().compactMap { note in
            if let folderID = filters.folderID, note.folderID != folderID {
                return nil
            }

            if let startDate = filters.startDate, note.createdAt < startDate {
                return nil
            }

            if let endDate = filters.endDate, note.createdAt > endDate {
                return nil
            }

            let folderName = note.folderID.flatMap { foldersByID[$0]?.name }
            let matches = searchMatches(in: note, query: normalizedQuery, folderName: folderName)
            guard !matches.isEmpty else { return nil }

            return NoteSearchResult(
                noteID: note.id,
                title: note.title,
                snippet: matches.first?.snippet ?? note.title,
                matchedFields: Array(Set(matches.flatMap { $0.fields })).sorted { $0.rawValue < $1.rawValue },
                folderName: folderName
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    public func template(id: UUID) -> NoteTemplate? {
        templatesByID[id]
    }

    public func allTemplates() -> [NoteTemplate] {
        templatesByID.values.sorted { lhs, rhs in
            if lhs.isDefault != rhs.isDefault {
                return lhs.isDefault && !rhs.isDefault
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    public var defaultTemplate: NoteTemplate {
        templatesByID[defaultTemplateID] ?? allTemplates().first ?? NoteTemplate.automatic
    }

    public func createShareLink(for note: MeetingNote, baseURL: URL) throws -> SharedNoteLink {
        guard note.shareSettings.privacyLevel != .private else {
            throw ShareError.privateNoteCannotBeShared
        }

        let linkID = UUID()
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let url = baseURL.appendingPathComponent("s").appendingPathComponent(token)
        let link = SharedNoteLink(
            id: linkID,
            noteID: note.id,
            token: token,
            url: url,
            settings: note.shareSettings,
            createdAt: Date(),
            revokedAt: nil
        )
        shareLinksByID[linkID] = link
        return link
    }

    public func revokeShareLink(linkID: UUID) {
        guard var link = shareLinksByID[linkID] else { return }
        link.revokedAt = Date()
        shareLinksByID[linkID] = link
    }

    public func shareLink(id: UUID) -> SharedNoteLink? {
        shareLinksByID[id]
    }

    @discardableResult
    public func insertFolder(_ folder: NoteFolder) -> NoteFolder {
        foldersByID[folder.id] = folder
        return folder
    }

    @discardableResult
    public func insertTemplate(_ template: NoteTemplate) -> NoteTemplate {
        templatesByID[template.id] = template
        if template.isDefault {
            defaultTemplateID = template.id
        }
        return template
    }

    @discardableResult
    public func insertEvent(_ event: CalendarEvent) -> CalendarEvent {
        events.append(event)
        return event
    }

    @discardableResult
    public func upsertNote(_ note: MeetingNote) -> MeetingNote {
        notesByID[note.id] = note
        return note
    }

    public func noteCount(in folderID: UUID) -> Int {
        notesByID.values.filter { $0.folderID == folderID }.count
    }

    private struct SearchMatch {
        let snippet: String
        let fields: [NoteSearchField]
    }

    private func searchMatches(in note: MeetingNote, query: String, folderName: String?) -> [SearchMatch] {
        var matches: [SearchMatch] = []
        if let hit = snippet(for: note.title, query: query) {
            matches.append(SearchMatch(snippet: hit, fields: [.title]))
        }
        if let hit = snippet(for: note.rawNotes, query: query) {
            matches.append(SearchMatch(snippet: hit, fields: [.rawNotes]))
        }

        if let hit = snippet(for: note.transcriptSegments.map(\.text).joined(separator: " "), query: query) {
            matches.append(SearchMatch(snippet: hit, fields: [.transcript]))
        }

        if let enhanced = note.enhancedNote {
            if let hit = snippet(for: enhanced.summary, query: query) {
                matches.append(SearchMatch(snippet: hit, fields: [.summary]))
            }

            let decisionsText = enhanced.decisions.joined(separator: " ")
            if let hit = snippet(for: decisionsText, query: query) {
                matches.append(SearchMatch(snippet: hit, fields: [.decisions]))
            }

            let actionItemsText = enhanced.actionItems.map(\.text).joined(separator: " ")
            if let hit = snippet(for: actionItemsText, query: query) {
                matches.append(SearchMatch(snippet: hit, fields: [.actionItems]))
            }
        }

        if let folderName, let hit = snippet(for: folderName, query: query) {
            matches.append(SearchMatch(snippet: hit, fields: [.folder]))
        }

        if let template = template(id: note.templateID ?? defaultTemplateID), let hit = snippet(for: template.name, query: query) {
            matches.append(SearchMatch(snippet: hit, fields: [.template]))
        }

        return matches
    }

    private func snippet(for text: String, query: String, radius: Int = 24) -> String? {
        let lowercasedText = text.lowercased()
        guard let range = lowercasedText.range(of: query) else { return nil }

        let lowerBound = lowercasedText.distance(from: lowercasedText.startIndex, to: range.lowerBound)
        let upperBound = lowercasedText.distance(from: lowercasedText.startIndex, to: range.upperBound)

        let start = max(0, lowerBound - radius)
        let end = min(text.count, upperBound + radius)

        let startIndex = text.index(text.startIndex, offsetBy: start)
        let endIndex = text.index(text.startIndex, offsetBy: end)
        let prefix = start > 0 ? "…" : ""
        let suffix = end < text.count ? "…" : ""
        return prefix + String(text[startIndex..<endIndex]) + suffix
    }
}

public final class DeterministicNoteGenerationService: NoteGenerationService {
    public init() {}

    public func generate(from request: NoteGenerationRequest) throws -> EnhancedNote {
        let summary: String
        if request.rawNotes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            summary = "Meeting recap for \(request.title)."
        } else {
            summary = request.rawNotes
        }

        let transcriptExcerpts = request.transcriptSegments.prefix(2).map { segment in
            SourceCitation(transcriptSegmentIDs: [segment.id], excerpt: segment.text)
        }

        let actionItems = request.transcriptSegments
            .filter { $0.text.lowercased().contains("action") || $0.text.lowercased().contains("follow up") }
            .map { ActionItem(text: $0.text, assignee: nil, dueDate: nil, status: .open) }

        return EnhancedNote(
            generatedAt: Date(),
            templateID: request.template.id,
            summary: summary,
            keyDiscussionPoints: request.rawNotes
                .split(separator: "\n")
                .map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            decisions: request.transcriptSegments
                .filter { $0.text.lowercased().contains("decided") }
                .map(\.text),
            risksOrOpenQuestions: request.transcriptSegments
                .filter { $0.text.lowercased().contains("risk") || $0.text.lowercased().contains("question") }
                .map(\.text),
            actionItems: actionItems,
            citations: Array(transcriptExcerpts)
        )
    }
}

extension NoteTemplate {
    public static let automatic = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
        kind: .automatic,
        name: "Automatic",
        description: "General-purpose note structure for most meetings.",
        instructions: "Summarize the meeting clearly, surface decisions and action items, and keep the summary concise.",
        sections: ["Summary", "Key discussion points", "Decisions", "Open questions", "Action items"],
        isDefault: true
    )

    public static let oneOnOne = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111112")!,
        kind: .oneOnOne,
        name: "1:1",
        description: "Reflection-oriented template for manager and peer 1:1s.",
        instructions: "Capture themes, progress, blockers, and follow-up items.",
        sections: ["Wins", "Blockers", "Topics", "Follow-ups"]
    )

    public static let standUp = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111113")!,
        kind: .standUp,
        name: "Stand-up",
        description: "Fast status template for daily team syncs.",
        instructions: "Emphasize progress, blockers, and explicit asks.",
        sections: ["Yesterday", "Today", "Blockers", "Asks"]
    )

    public static let interview = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111114")!,
        kind: .interview,
        name: "Interview",
        description: "Structured template for hiring and research conversations.",
        instructions: "Keep evaluation criteria separate from evidence and follow-up.",
        sections: ["Context", "Evidence", "Assessment", "Follow-up"]
    )

    public static let customerCall = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111115")!,
        kind: .customerCall,
        name: "Customer call",
        description: "Template for discovery, support, and account conversations.",
        instructions: "Highlight pain points, requests, objections, and commitments.",
        sections: ["Goals", "Pain points", "Requests", "Next steps"]
    )

    public static let projectReview = NoteTemplate(
        id: UUID(uuidString: "11111111-1111-1111-1111-111111111116")!,
        kind: .projectReview,
        name: "Project review",
        description: "Template for planning, review, and decision meetings.",
        instructions: "Focus on progress, decision points, risks, and assignments.",
        sections: ["Status", "Decisions", "Risks", "Action items"]
    )

    public static var builtInTemplates: [NoteTemplate] {
        [automatic, oneOnOne, standUp, interview, customerCall, projectReview]
    }
}
