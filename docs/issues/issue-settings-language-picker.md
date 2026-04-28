## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Add a Transcription Language picker to the existing Settings view. The picker offers "Auto-detect" plus an explicit list of languages (BCP 47 primary languages — regional variants are deferred). The choice writes to `LocalTranscriptionConfiguration.preferredLocaleIdentifier`, which already flows through the pipeline. A short non-modal explanation states that auto-detect is slower than locking a language and requires a multilingual Whisper model. When the active backend is Apple Speech (because Whisper is unavailable), the picker shows a hint that auto-detect requires Whisper and that Apple Speech will run in the system locale instead.

Default value selection: if the user has not chosen anything, the picker reflects the resolved system locale's primary language as the default selection.

## Acceptance criteria

- [ ] Settings exposes a Transcription Language control alongside the existing transcription backend and policy controls.
- [ ] The control offers "Auto-detect" plus a curated list of languages.
- [ ] Choosing a language writes to `LocalTranscriptionConfiguration.preferredLocaleIdentifier` and is persisted across app restarts.
- [ ] A short, non-modal explanation states that auto-detect is slower than locking a language and requires a multilingual Whisper model.
- [ ] When the active backend is Apple Speech, an additional hint clarifies that auto-detect requires Whisper.
- [ ] When the active backend is Apple Speech and the user has chosen "Auto-detect", the runtime status (`TranscriptionBackendStatus.availability`) reflects `degraded` and the detail message says auto-detect is not available with Apple Speech.
- [ ] If the user has never made a choice, the picker reflects the system locale's primary language as the default visible value.
- [ ] UI tests verify the picker is present, persists across reopens, and that the runtime status reacts to backend availability.
- [ ] Existing transcription tests continue to pass.

## Out of scope

- Regional variants (e.g. `es-ES` vs `es-MX`). Carry as a TBD; the BCP 47 schema lets us defer.
- Curated multilingual model download UI (next slice).
- Note-detail "Detected" header and re-transcribe UI.
- Localizing the picker labels into other languages (app chrome stays English in this milestone).

## Open questions

- Should the picker offer regional variants now or only primary languages? Default for this slice: primary languages only.

## Blocked by

- `issue-whisper-model-classifier-and-auto-routing.md`

## User stories addressed

- User story 5
- User story 6
- User story 12
- User story 13
- User story 21
- User story 22
- User story 23
- User story 30
