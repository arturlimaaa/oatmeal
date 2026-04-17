import Foundation
import OatmealEdge
import OatmealCore

struct AppPersistenceSnapshot: Codable, Equatable, Sendable {
    var notes: [MeetingNote]
    var selectedTemplateID: UUID?
    var transcriptionConfiguration: LocalTranscriptionConfiguration

    init(
        notes: [MeetingNote] = [],
        selectedTemplateID: UUID? = nil,
        transcriptionConfiguration: LocalTranscriptionConfiguration = .default
    ) {
        self.notes = notes
        self.selectedTemplateID = selectedTemplateID
        self.transcriptionConfiguration = transcriptionConfiguration
    }

    static let empty = AppPersistenceSnapshot()

    private enum CodingKeys: String, CodingKey {
        case notes
        case selectedTemplateID
        case transcriptionConfiguration
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        notes = try container.decodeIfPresent([MeetingNote].self, forKey: .notes) ?? []
        selectedTemplateID = try container.decodeIfPresent(UUID.self, forKey: .selectedTemplateID)
        transcriptionConfiguration = try container.decodeIfPresent(
            LocalTranscriptionConfiguration.self,
            forKey: .transcriptionConfiguration
        ) ?? .default
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(notes, forKey: .notes)
        try container.encodeIfPresent(selectedTemplateID, forKey: .selectedTemplateID)
        try container.encode(transcriptionConfiguration, forKey: .transcriptionConfiguration)
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
        selectedTemplateID: UUID?,
        transcriptionConfiguration: LocalTranscriptionConfiguration
    ) throws {
        try save(
            AppPersistenceSnapshot(
                notes: notes,
                selectedTemplateID: selectedTemplateID,
                transcriptionConfiguration: transcriptionConfiguration
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
