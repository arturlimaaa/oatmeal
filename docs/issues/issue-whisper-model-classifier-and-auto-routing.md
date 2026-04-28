## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Introduce a `WhisperModelClassifier` deep module that distinguishes English-only `.en` Whisper variants from multilingual variants and identifies size tiers. Extend `LocalModelInventory` to expose the classification on each discovered model. Promote `LanguagePolicy` from the minimal tracer-bullet implementation to its full form: it now picks the right model variant for the user's language configuration, blocks auto-detect when only `.en` models are available, and surfaces a user-facing blocking reason in that case.

This slice makes the "no regression for English users who lock to English" guarantee real: when a user is locked to English and has both `small.en.bin` and `medium.bin` installed, the policy continues to use `small.en.bin` with `-l en`. When the user is on auto-detect and only has `.en` models, the policy returns a blocked decision with a reason that downstream code can surface to the user.

## Acceptance criteria

- [ ] `WhisperModelClassifier` classifies each discovered model into `(variant: englishOnly | multilingual, sizeTier: tiny | base | small | medium | large | other)` based on filename conventions.
- [ ] `LocalModelInventory` exposes the classification on each discovered `ManagedLocalModel` (or via a parallel API that consumers can use without breaking existing code).
- [ ] `LanguagePolicy` prefers `.en` variants when the configured language is English and a `.en` model is present.
- [ ] `LanguagePolicy` prefers multilingual variants when the configured language is non-English or auto-detect.
- [ ] When auto-detect is configured but only `.en` models are present, `LanguagePolicy` returns a blocked decision with a user-facing reason describing what to do (download a multilingual model).
- [ ] When a specific non-English language is configured but only `.en` models are present, `LanguagePolicy` returns the same blocked decision.
- [ ] The blocking reason is surfaced through the existing `TranscriptionBackendStatus.detail` mechanism so it appears in the runtime status today.
- [ ] Tabular unit tests cover `WhisperModelClassifier` across `.en` variants, multilingual variants, ambiguous filenames, and unknown size tiers.
- [ ] Tabular unit tests cover the expanded `LanguagePolicy` across at least: English-locked with `.en` available, English-locked with multilingual-only, auto-detect with multilingual model, auto-detect with `.en`-only (blocked), specific non-English with multilingual model, specific non-English with `.en`-only (blocked), no models at all.
- [ ] Existing English transcription continues to work end-to-end with both `.en` and multilingual models.

## Out of scope

- Settings UI for language picker (next slice).
- Settings UI for model catalog and downloads.
- Note-detail UI for the detected-language header.
- Surfacing the blocking reason as a Settings-level call-to-action (will be addressed in the curated catalog slice).

## Blocked by

- `issue-multilingual-transcription-tracer-bullet.md`

## User stories addressed

- User story 11
- User story 14
- User story 15
- User story 29
- User story 30
- User story 38
- User story 43
