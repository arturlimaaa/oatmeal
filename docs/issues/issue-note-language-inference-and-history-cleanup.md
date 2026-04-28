## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Close out the milestone. Introduce a `NoteLanguageInference` deep module that derives a note's primary language from a list of segments with optional language tags, used when persisting a re-transcribed note where the per-segment values diverge from the previous primary language. Audit the codebase for any remaining English-only assumptions surfaced during the prior phases, surface or remove them per the PRD scope. Confirm that the privacy/status messaging in the capture UI accurately reflects the new retention behavior. Add the documentation note in `docs/` describing the multilingual pipeline behavior, as a reference for support and future maintenance.

This is intentionally a smaller, hygiene-focused slice. It does not introduce new user-facing capability; it ensures the milestone is internally consistent and the deep modules listed in the PRD are all extracted as designed.

## Acceptance criteria

- [ ] A `NoteLanguageInference` module exists with a pure-function interface that takes `[TranscriptSegment]` and returns the inferred primary language.
- [ ] The re-transcribe path uses `NoteLanguageInference` when computing the note's primary `language` field.
- [ ] Tabular unit tests cover `NoteLanguageInference` across all-same, mixed, mostly-nil, and all-nil segment language distributions.
- [ ] An audit pass identifies any remaining English-only string matches in the transcription pipeline (excluding meeting-platform detection, which is documented out of scope) and removes or generalizes them.
- [ ] The capture UI's privacy/status string is verified end-to-end against the actual retention behavior introduced in the retention slice.
- [ ] A short reference note in `docs/` describes the multilingual pipeline's contract: what is detected where, what is persisted, how re-transcribe works, and what is left for future milestones.
- [ ] All deep modules listed in the parent PRD (`LanguagePolicy`, `WhisperModelClassifier`, `CuratedModelCatalog`, `AudioRetentionCoordinator`, `WhisperJSONParser` extension, `NoteLanguageInference`, `PromptTemplateLocalizer`) are extracted with the intended interfaces and have their own unit tests.
- [ ] Existing test suites pass.

## Out of scope

- App chrome localization.
- Translating browser meeting detection regexes (out of scope for this milestone per the PRD).
- Code-switching support.
- Streaming/near-live multilingual transcription.

## Blocked by

- `issue-prompt-template-localizer-and-remove-deterministic-fallback.md`
- `issue-note-detail-detected-language-and-retranscribe-ui.md`
- `issue-settings-curated-model-catalog-and-download.md`

## User stories addressed

- User story 33
- User story 43
- User story 44
- User story 45
