## Parent PRD

`docs/prd-multilingual-transcription-pipeline.md`

## What to build

Make the notes pipeline source-language-aware. Introduce a `PromptTemplateLocalizer` deep module that produces a target-language system prompt for the top-N supported languages and falls back to an English prompt with an explicit "respond in <language>" instruction for tail languages. JSON structural keys (e.g. `action_items`) remain English regardless of language. Wire the localizer into both the local MLX path and the remote API path.

Remove `DeterministicNoteGenerationService` entirely. When neither a local MLX model nor a remote API is configured, surface a clear "configure an LLM in Settings" error rather than silently producing empty or English-keyword-grepped notes. The existing prompt templates in `OatmealServices.swift` continue to drive the LLM paths but are no longer consumed by a deterministic fallback.

## Acceptance criteria

- [ ] A `PromptTemplateLocalizer` module exists with a pure-function interface that takes `(template, targetLanguage)` and returns the localized system prompt and the structural keys (which remain English).
- [ ] For each supported translated language, the returned system prompt is in that language and structural keys are unchanged.
- [ ] For a tail language, the localizer returns the English prompt augmented with an explicit "respond in <language>" directive.
- [ ] Both the local MLX summary backend and the remote API path consume `PromptTemplateLocalizer` to construct their requests.
- [ ] `DeterministicNoteGenerationService` is removed and all references are cleaned up.
- [ ] When no LLM path is available, the note generation pipeline surfaces a "configure an LLM in Settings" error that is presented to the user without ambiguity.
- [ ] Tabular unit tests cover `PromptTemplateLocalizer` across each supported language and at least one tail language.
- [ ] Existing note-generation tests for the LLM paths continue to pass.

## Out of scope

- Translating note section labels in the UI (e.g. the "Decisions" / "Action items" headings remain English in the app chrome — note content is in the source language but the surrounding UI is not localized in this milestone).
- Configuring multiple remote API providers.
- Local MLX model selection per language (the existing model is reused).

## Open questions

- What is the initial list of "supported languages" for translated system prompts (top 5 vs top 10)? Resolve before merging.

## Blocked by

- `issue-multilingual-transcription-tracer-bullet.md`

## User stories addressed

- User story 3
- User story 4
- User story 24
- User story 25
- User story 34
- User story 35
- User story 36
- User story 42
- User story 43
