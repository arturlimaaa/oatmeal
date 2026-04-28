## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Add a "Multilingual models" section to Settings that lists curated downloadable Whisper models with size and per-language quality guidance, plus an explicit one-click download for each. Downloads write to the existing managed models directory so `LocalModelInventory` picks them up automatically. The list is backed by a new `CuratedModelCatalog` data structure. When the user is on auto-detect or a non-English language but has only `.en` models installed, the runtime status surfaces a call-to-action that links to this Settings section.

The download flow is fully explicit: the user clicks a download button, sees a progress indicator, and can cancel. There is no silent or auto-download path.

## Acceptance criteria

- [ ] A `CuratedModelCatalog` data structure lists known-good multilingual Whisper models with `(displayName, sizeBytes, downloadURL, perLanguageQualityHints)`.
- [ ] `CuratedModelCatalog` exposes a recommendation function that ranks models for a target language, used by the Settings UI.
- [ ] Settings adds a "Multilingual models" section that renders the catalog with size, quality guidance, and a download button per entry.
- [ ] Clicking download fetches the model into the managed models directory, shows progress, and supports cancellation.
- [ ] Models that are already installed are shown as installed rather than offering a redundant download.
- [ ] When `LanguagePolicy` returns a blocked decision because only `.en` models are available, the call-to-action surfaced in the runtime status links to or otherwise points the user toward this Settings section.
- [ ] Tabular unit tests cover the recommendation function across target languages.
- [ ] UI tests verify the catalog renders, that an install state is reflected after a successful download, and that cancellation cleans up partial files.

## Out of scope

- Auto-download of any model. All downloads are explicit clicks.
- Background or scheduled downloads.
- Migrating users away from existing `.en` models.
- Removing models from disk via Settings (delete via Finder remains the path).

## Open questions

- What is the canonical download source for the curated multilingual Whisper models — Hugging Face direct links or a vendored CDN? Resolve before merging the first concrete catalog entry.
- What is the initial set of catalog entries? Resolve based on telemetry or design call.

## Blocked by

- `issue-whisper-model-classifier-and-auto-routing.md`
- `issue-settings-language-picker.md`

## User stories addressed

- User story 15
- User story 16
- User story 17
- User story 20
- User story 39
