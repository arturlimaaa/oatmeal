## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Deliver the thinnest possible end-to-end multilingual path. Add language fields to the data model, extract the detected language from whisper.cpp's JSON output, introduce a minimal `LanguagePolicy` module that maps the existing `preferredLocaleIdentifier` to the language argument passed to whisper, and persist the detected language onto the note and its transcription attempt. No Settings UI, no note-detail UI, no model classification — just a verifiable vertical slice that proves a Spanish audio file flows through the pipeline as Spanish and lands in storage tagged as Spanish.

The `LanguagePolicy` module starts simple but with the right shape: pure function, no I/O, returns the language argument, the model to use (today: just the first discovered model), and any blocking reason. Subsequent tickets layer auto-routing and `.en` blocking on top.

## Acceptance criteria

- [ ] `TranscriptSegment` carries an optional BCP 47 `language` field, decoded with `decodeIfPresent` for backwards compatibility.
- [ ] `MeetingNote` carries an optional BCP 47 `language` field, decoded with `decodeIfPresent`.
- [ ] `NoteTranscriptionAttempt` carries an optional BCP 47 `language` field.
- [ ] `TranscriptionJobResult` carries an optional `detectedLanguage` field.
- [ ] `WhisperJSONParser` extracts the detected language from whisper.cpp JSON output and gracefully handles output where the field is missing.
- [ ] A `LanguagePolicy` module exists with a pure-function interface that takes `(configuredLocale, discoveredModels, activeBackend)` and returns `(whisperLanguageArg, modelToUse, isDegraded, blockingReason?)`.
- [ ] Today's behavior is preserved: when `preferredLocaleIdentifier` is `nil`, `LanguagePolicy` returns `"auto"`; when it carries an identifier, `LanguagePolicy` extracts the BCP 47 language code.
- [ ] After a successful Whisper transcription, the detected language is persisted on the resulting `MeetingNote` and on the new `NoteTranscriptionAttempt` entry.
- [ ] Tabular unit tests cover `LanguagePolicy` (auto with no locale, locked English, locked non-English, missing models) and `WhisperJSONParser` (language present, language missing).
- [ ] An end-to-end test against the mock backend (extended to populate `detectedLanguage`) verifies that the language flows from `TranscriptionJobResult` into `MeetingNote.language` and `NoteTranscriptionAttempt.language`.
- [ ] Existing English transcription tests continue to pass unchanged.

## Out of scope

- Audio retention changes (handled in the next slice).
- Multi-model auto-routing or `.en` blocking (handled in the classifier slice).
- Settings UI for language picker.
- Note-detail UI for showing or overriding the detected language.
- Removing `DeterministicNoteGenerationService` or refactoring prompt templates.

## Blocked by

None - can start immediately.

## User stories addressed

- User story 1
- User story 2
- User story 7
- User story 31
- User story 32
- User story 33
- User story 37
- User story 41
- User story 43
- User story 44
- User story 45
