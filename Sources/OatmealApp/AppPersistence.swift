import Foundation
import OatmealEdge
import OatmealCore

struct AppPersistenceSnapshot: Codable, Equatable, Sendable {
    var notes: [MeetingNote]
    var selectedSidebarItem: SidebarItem?
    var selectedUpcomingEventID: UUID?
    var selectedNoteID: UUID?
    var selectedNoteWorkspaceMode: NoteWorkspaceMode?
    var selectedTemplateID: UUID?
    var collapsedSessionControllerPresentationIdentity: String?
    var pendingMeetingDetection: PendingMeetingDetection?
    var meetingDetectionConfiguration: MeetingDetectionConfiguration
    var transcriptionConfiguration: LocalTranscriptionConfiguration
    var summaryConfiguration: LocalSummaryConfiguration

    init(
        notes: [MeetingNote] = [],
        selectedSidebarItem: SidebarItem? = nil,
        selectedUpcomingEventID: UUID? = nil,
        selectedNoteID: UUID? = nil,
        selectedNoteWorkspaceMode: NoteWorkspaceMode? = nil,
        selectedTemplateID: UUID? = nil,
        collapsedSessionControllerPresentationIdentity: String? = nil,
        pendingMeetingDetection: PendingMeetingDetection? = nil,
        meetingDetectionConfiguration: MeetingDetectionConfiguration = .default,
        transcriptionConfiguration: LocalTranscriptionConfiguration = .default,
        summaryConfiguration: LocalSummaryConfiguration = .default
    ) {
        self.notes = notes
        self.selectedSidebarItem = selectedSidebarItem
        self.selectedUpcomingEventID = selectedUpcomingEventID
        self.selectedNoteID = selectedNoteID
        self.selectedNoteWorkspaceMode = selectedNoteWorkspaceMode
        self.selectedTemplateID = selectedTemplateID
        self.collapsedSessionControllerPresentationIdentity = collapsedSessionControllerPresentationIdentity
        self.pendingMeetingDetection = pendingMeetingDetection
        self.meetingDetectionConfiguration = meetingDetectionConfiguration
        self.transcriptionConfiguration = transcriptionConfiguration
        self.summaryConfiguration = summaryConfiguration
    }

    static let empty = AppPersistenceSnapshot()

    private enum CodingKeys: String, CodingKey {
        case notes
        case selectedSidebarItem
        case selectedUpcomingEventID
        case selectedNoteID
        case selectedNoteWorkspaceMode
        case selectedTemplateID
        case collapsedSessionControllerPresentationIdentity
        case pendingMeetingDetection
        case meetingDetectionConfiguration
        case transcriptionConfiguration
        case summaryConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decodeIfPresent([MeetingNote].self, forKey: .notes) ?? []
        selectedSidebarItem = try container.decodeIfPresent(SidebarItem.self, forKey: .selectedSidebarItem)
        selectedUpcomingEventID = try container.decodeIfPresent(UUID.self, forKey: .selectedUpcomingEventID)
        selectedNoteID = try container.decodeIfPresent(UUID.self, forKey: .selectedNoteID)
        selectedNoteWorkspaceMode = try container.decodeIfPresent(
            NoteWorkspaceMode.self,
            forKey: .selectedNoteWorkspaceMode
        )
        selectedTemplateID = try container.decodeIfPresent(UUID.self, forKey: .selectedTemplateID)
        collapsedSessionControllerPresentationIdentity = try container.decodeIfPresent(
            String.self,
            forKey: .collapsedSessionControllerPresentationIdentity
        )
        pendingMeetingDetection = try container.decodeIfPresent(
            PendingMeetingDetection.self,
            forKey: .pendingMeetingDetection
        )
        meetingDetectionConfiguration = try container.decodeIfPresent(
            MeetingDetectionConfiguration.self,
            forKey: .meetingDetectionConfiguration
        ) ?? .default
        transcriptionConfiguration = try container.decodeIfPresent(
            LocalTranscriptionConfiguration.self,
            forKey: .transcriptionConfiguration
        ) ?? .default
        summaryConfiguration = try container.decodeIfPresent(
            LocalSummaryConfiguration.self,
            forKey: .summaryConfiguration
        ) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(selectedSidebarItem, forKey: .selectedSidebarItem)
        try container.encodeIfPresent(selectedUpcomingEventID, forKey: .selectedUpcomingEventID)
        try container.encodeIfPresent(selectedNoteID, forKey: .selectedNoteID)
        try container.encodeIfPresent(selectedNoteWorkspaceMode, forKey: .selectedNoteWorkspaceMode)
        try container.encodeIfPresent(selectedTemplateID, forKey: .selectedTemplateID)
        try container.encodeIfPresent(
            collapsedSessionControllerPresentationIdentity,
            forKey: .collapsedSessionControllerPresentationIdentity
        )
        try container.encodeIfPresent(pendingMeetingDetection, forKey: .pendingMeetingDetection)
        try container.encode(meetingDetectionConfiguration, forKey: .meetingDetectionConfiguration)
        try container.encode(transcriptionConfiguration, forKey: .transcriptionConfiguration)
        try container.encode(summaryConfiguration, forKey: .summaryConfiguration)
    }
}

final class AppPersistence: @unchecked Sendable {
    static let shared = AppPersistence()

    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let applicationSupportFolderName: String
    private let stateFileName: String

    init(
        fileManager: FileManager = .default,
        applicationSupportFolderName: String = "Oatmeal",
        stateFileName: String = "AppState.json"
    ) {
        self.fileManager = fileManager
        self.applicationSupportFolderName = applicationSupportFolderName
        self.stateFileName = stateFileName

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .deferredToDate
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        self.decoder = decoder
    }

    var applicationSupportDirectoryURL: URL {
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        return baseURL.appendingPathComponent(applicationSupportFolderName, isDirectory: true)
    }

    var stateFileURL: URL {
        applicationSupportDirectoryURL.appendingPathComponent(stateFileName, isDirectory: false)
    }

    func load() throws -> AppPersistenceSnapshot {
        let url = stateFileURL
        guard fileManager.fileExists(atPath: url.path) else {
            return .empty
        }

        let data = try Data(contentsOf: url)
        return try decoder.decode(AppPersistenceSnapshot.self, from: data)
    }

    func loadOrEmpty() -> AppPersistenceSnapshot {
        (try? load()) ?? .empty
    }

    func save(_ snapshot: AppPersistenceSnapshot) throws {
        try ensureApplicationSupportDirectoryExists()

        let data = try encoder.encode(snapshot)
        try data.write(to: stateFileURL, options: [.atomic])
    }

    func save(
        notes: [MeetingNote],
        selectedSidebarItem: SidebarItem,
        selectedUpcomingEventID: UUID?,
        selectedNoteID: UUID?,
        selectedNoteWorkspaceMode: NoteWorkspaceMode,
        selectedTemplateID: UUID?,
        collapsedSessionControllerPresentationIdentity: String?,
        pendingMeetingDetection: PendingMeetingDetection?,
        meetingDetectionConfiguration: MeetingDetectionConfiguration,
        transcriptionConfiguration: LocalTranscriptionConfiguration,
        summaryConfiguration: LocalSummaryConfiguration
    ) throws {
        try save(
            AppPersistenceSnapshot(
                notes: notes,
                selectedSidebarItem: selectedSidebarItem,
                selectedUpcomingEventID: selectedUpcomingEventID,
                selectedNoteID: selectedNoteID,
                selectedNoteWorkspaceMode: selectedNoteWorkspaceMode,
                selectedTemplateID: selectedTemplateID,
                collapsedSessionControllerPresentationIdentity: collapsedSessionControllerPresentationIdentity,
                pendingMeetingDetection: pendingMeetingDetection,
                meetingDetectionConfiguration: meetingDetectionConfiguration,
                transcriptionConfiguration: transcriptionConfiguration,
                summaryConfiguration: summaryConfiguration
            )
        )
    }

    private func ensureApplicationSupportDirectoryExists() throws {
        let directoryURL = applicationSupportDirectoryURL
        if fileManager.fileExists(atPath: directoryURL.path) {
            return
        }

        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }
}
