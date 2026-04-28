## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Move the normalized 16 kHz mono WAV out of the per-job temp directory and into a stable per-note location, delete the original 48 kHz capture artifacts after normalization, and introduce a re-transcribe pipeline that consumes the retained WAV with a caller-provided language. This slice has no UI surface — re-transcribe is exposed as a programmatic API, exercised only in tests.

The retention rules are encapsulated in a new `AudioRetentionCoordinator` deep module so that the cleanup logic scattered across `MeetingCaptureEngine.clearExistingRecordingFiles` and `AppViewModel`'s post-success cleanup lives in one place. The coordinator is the single source of truth for what audio is kept and when it is deleted.

This slice changes the privacy posture: the 48 kHz source is destroyed earlier than today, but the 16 kHz normalized WAV survives until the note is deleted. The retention message in the capture UI is updated to match the actual behavior.

## Acceptance criteria

- [ ] An `AudioRetentionCoordinator` module owns the retention policy: given `(note, captureArtifacts, lifecycleEvent)` it decides what to keep and what to delete.
- [ ] The audio normalization output is written to a stable per-note path under the recordings directory rather than to a temp job directory that gets removed after the run.
- [ ] After successful normalization, the original `.caf` microphone file and `.mp4` system audio file are deleted.
- [ ] The retained normalized WAV is deleted only when its note is deleted.
- [ ] A re-transcribe API exists on the transcription pipeline that accepts `(noteID, language)` and runs Whisper against the retained WAV with the chosen language, appending a new entry to the note's transcription history.
- [ ] The re-transcribe API returns a clear error when no retained WAV exists for the given note.
- [ ] Existing English transcription continues to work end-to-end.
- [ ] The privacy/status string surfaced in the capture UI accurately describes the new retention behavior ("Original recording deleted after transcription; compressed copy retained for re-processing").
- [ ] Tabular unit tests cover `AudioRetentionCoordinator` across artifact states (pre-normalization, post-normalization, post-note-deletion) using a `FileManager` shim.
- [ ] An integration test exercises the re-transcribe path against a fixture: transcribe → override language → re-transcribe → assert two history entries with different languages and the same retained WAV.

## Out of scope

- UI for triggering re-transcribe (handled in the note-detail slice).
- Multi-model auto-routing or `.en` blocking.
- Settings UI for language picker.
- Migration of existing on-disk notes from the old retention layout. New notes use the new layout; pre-existing notes continue to work without retained audio (re-transcribe is unavailable for them, which is the documented behavior).

## Blocked by

- `issue-multilingual-transcription-tracer-bullet.md`

## User stories addressed

- User story 8
- User story 9
- User story 18
- User story 19
- User story 26
- User story 27
- User story 28
- User story 40
- User story 43
