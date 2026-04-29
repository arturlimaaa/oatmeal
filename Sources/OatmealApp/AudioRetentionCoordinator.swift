import Foundation

/// Single decision point for what audio Oatmeal keeps and when it is deleted.
///
/// The coordinator owns the on-disk layout for every audio artifact tied to a
/// note: the original 48 kHz `.caf` microphone capture, the original 48 kHz
/// `.mp4` system-audio capture, and the 16 kHz mono WAV that Whisper consumes.
/// It exposes a small interface to two callers — the post-success cleanup
/// path in `AppViewModel` and the note-deletion path — so that the retention
/// rules live in one place rather than scattered across capture cleanup and
/// post-processing.
///
/// Retention rules implemented here:
/// - Before normalization: all three artifacts may exist; the coordinator
///   simply reports their stable paths so the capture pipeline writes to
///   them.
/// - On `normalizationSucceeded`: delete the original `.caf` and `.mp4`
///   captures. The normalized WAV is left alone because the Whisper backend
///   wrote it to the same stable per-note path the coordinator reports.
/// - On `noteDeleted`: delete the normalized WAV if it still exists.
///
/// The coordinator is a deep module: a small surface (`paths`, `apply`,
/// `retainedWAVURL`) and a clear retention policy underneath. Tests exercise
/// it with a temp-dir-backed `FileManager`.
struct AudioRetentionCoordinator {
    enum LifecycleEvent: Equatable {
        case normalizationSucceeded(noteID: UUID)
        case noteDeleted(noteID: UUID)
    }

    struct Paths: Equatable {
        let microphoneURL: URL
        let systemAudioURL: URL
        let normalizedWAVURL: URL
    }

    private let recordingsDirectoryURL: URL
    private let fileManager: FileManager

    init(recordingsDirectoryURL: URL, fileManager: FileManager = .default) {
        self.recordingsDirectoryURL = recordingsDirectoryURL
        self.fileManager = fileManager
    }

    /// The on-disk layout for a note's audio artifacts. The caller is
    /// responsible for creating parent directories as needed before writing,
    /// either through this type's `prepareNormalizedDirectory()` helper or
    /// through the existing capture-engine directory preparation.
    func paths(for noteID: UUID) -> Paths {
        Paths(
            microphoneURL: recordingsDirectoryURL.appendingPathComponent(
                "\(noteID.uuidString).caf",
                isDirectory: false
            ),
            systemAudioURL: recordingsDirectoryURL.appendingPathComponent(
                "\(noteID.uuidString).mp4",
                isDirectory: false
            ),
            normalizedWAVURL: normalizedDirectoryURL.appendingPathComponent(
                "\(noteID.uuidString).wav",
                isDirectory: false
            )
        )
    }

    /// Returns the retained normalized WAV URL when it still exists on disk,
    /// otherwise `nil`. Callers use this to decide whether re-transcribe is
    /// available for a note.
    func retainedWAVURL(for noteID: UUID) -> URL? {
        let url = paths(for: noteID).normalizedWAVURL
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    /// Ensures the directory that holds normalized WAVs exists and returns
    /// its URL. Call this before asking the Whisper backend to write to the
    /// per-note normalized WAV path.
    @discardableResult
    func prepareNormalizedDirectory() throws -> URL {
        let directoryURL = normalizedDirectoryURL
        if !fileManager.fileExists(atPath: directoryURL.path) {
            try fileManager.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: true
            )
        }
        return directoryURL
    }

    /// Apply a lifecycle event to the on-disk artifacts for a note.
    ///
    /// Missing files are not an error: the coordinator is idempotent so that
    /// repeated calls (e.g. re-running cleanup after a partial failure) do
    /// not throw.
    func apply(_ event: LifecycleEvent) throws {
        switch event {
        case let .normalizationSucceeded(noteID):
            let paths = paths(for: noteID)
            try removeIfExists(paths.microphoneURL)
            try removeIfExists(paths.systemAudioURL)
            try removeDirectoryIfExists(liveChunkDirectoryURL(for: noteID))
        case let .noteDeleted(noteID):
            let paths = paths(for: noteID)
            try removeIfExists(paths.normalizedWAVURL)
        }
    }

    private var normalizedDirectoryURL: URL {
        recordingsDirectoryURL.appendingPathComponent("Normalized", isDirectory: true)
    }

    private func liveChunkDirectoryURL(for noteID: UUID) -> URL {
        recordingsDirectoryURL
            .appendingPathComponent("LiveChunks", isDirectory: true)
            .appendingPathComponent(noteID.uuidString, isDirectory: true)
    }

    private func removeIfExists(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    private func removeDirectoryIfExists(_ url: URL) throws {
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}
