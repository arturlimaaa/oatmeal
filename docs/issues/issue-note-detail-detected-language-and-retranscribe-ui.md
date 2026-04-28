## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Surface the detected language on the note-detail view and make re-transcribe a one-click recovery flow. The note header displays "Detected: <Language>" with a dropdown override. Choosing a different language triggers the re-transcribe API delivered in the audio retention slice. The transcription history view shows the language used for each prior attempt.

When a note has no retained normalized WAV (legacy notes, or notes whose retained audio has been deleted), the override dropdown is hidden or clearly disabled with an explanation, rather than offering a button that produces a confusing failure.

## Acceptance criteria

- [ ] The note-detail view shows the detected language in the note header for any note that has a persisted `language` value.
- [ ] A dropdown lets the user override the language and trigger a re-transcribe of the same audio.
- [ ] Triggering a re-transcribe runs Whisper against the retained WAV with the chosen language, appends a new `NoteTranscriptionAttempt` entry, updates the note's `language`, and refreshes the transcript view.
- [ ] During re-transcription, the UI shows progress feedback consistent with the existing transcription progress UI.
- [ ] When the note has no retained WAV, the override is hidden or disabled with a one-line explanation.
- [ ] The transcription history view shows the language for each historical attempt.
- [ ] UI tests verify: detected language renders, override triggers re-transcribe and updates the note, the disabled state is shown when no audio is retained, and history reflects the per-attempt language.
- [ ] Existing note-detail tests continue to pass.

## Out of scope

- Triggering re-transcribe from anywhere other than the override dropdown (no batch re-transcribe across notes).
- Multi-pass auto-detect retries (one re-transcribe per user click).
- Localizing the language names in the dropdown into other languages.

## Blocked by

- `issue-audio-retention-coordinator-and-retranscribe-api.md`
- `issue-settings-language-picker.md`

## User stories addressed

- User story 7
- User story 8
- User story 9
- User story 10
- User story 28
- User story 45
