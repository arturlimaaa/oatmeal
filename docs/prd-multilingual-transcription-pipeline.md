## Problem Statement

Oatmeal's transcription pipeline silently assumes English. The plumbing for non-English transcription technically exists (whisper.cpp supports 99+ languages, the `LocalTranscriptionConfiguration.preferredLocaleIdentifier` field is threaded through the pipeline, and `SFSpeechRecognizer` accepts arbitrary locales), but the user-facing experience and the downstream notes pipeline both behave as if every meeting is in English.

For a bilingual user — someone who speaks English plus at least one other language and routinely has meetings in either — that means:

- there is no Settings affordance to choose a transcription language or enable auto-detect, so meetings in the user's non-English language transcribe through whatever the system locale resolves to and frequently produce garbage
- the deterministic note fallback (`DeterministicNoteGenerationService`) extracts action items by substring-matching English keywords like `"action"`, `"follow up"`, `"decided"`, `"risk"`, `"question"`, so a Spanish meeting silently produces empty notes
- there is no way for the user to recover from a wrong-language transcription after the fact, because the source audio is deleted as soon as the note is generated successfully
- discovered Whisper models are treated identically regardless of whether they are English-only (`.en` variants, which physically cannot transcribe other languages or auto-detect) or multilingual, so a user with a `small.en.bin` who turns on auto-detect would get garbage with no warning

The product positions itself as a local-first meeting engine with the tagline "Audio stays on this Mac. Transcribing locally." That promise is broken for any user whose meetings are not in English. At the same time, English-only users today benefit from the smaller and faster `.en` model variants, and any naive "go multilingual" approach risks regressing their transcription latency by 2-3x by pushing them onto larger multilingual models.

This milestone makes Oatmeal credibly multilingual at the transcription layer without regressing the English-only user, and without expanding scope into full app localization.

## Solution

Make the transcription pipeline language-aware end to end, with auto-detect as the default for users who configure it and an explicit language picker for users who want to lock in a single language for performance.

From the user's perspective:

- Settings exposes a Transcription Language picker with "Auto-detect" plus an explicit list of languages
- when a meeting transcribes, the detected language is shown on the note and the original speaker's language is preserved through the entire pipeline — the transcript is in the source language, the summary is in the source language, and action items are phrased in the source language
- if auto-detect picked the wrong language, the user can override the language on the note and re-transcribe the same audio without re-recording
- the curated model picker in Settings makes it easy to download the right multilingual Whisper model for the languages the user actually uses, with size and quality guidance
- a user who only ever has English meetings can lock the language to English in Settings and keep using the small `.en` model and the fast `-l en` path with no performance regression
- when no Whisper installation is available, Apple Speech is still used as a degraded fallback that runs in the user's system locale, with a clear hint that auto-detect requires Whisper
- when no LLM path (local MLX or remote API) is available at all, the app stops pretending it can generate notes from substring matching and instead surfaces a clear "configure an LLM" message

App chrome stays in English for this milestone. The audience is users who already operate comfortably in English UI but conduct meetings in their other languages.

This milestone explicitly optimizes for:

- correctness on non-English meetings end to end
- zero performance regression for users who lock their language to English
- a recovery path for the inevitable wrong-language detection without forcing users to re-record
- preserving the local-first privacy posture, including for the multilingual model download flow

This milestone does not promise: localized app chrome, RTL UI, code-switching within a single meeting, or per-segment language detection in the user-visible UI (the data model is forward-compatible with code-switching but the product surface treats one meeting as one language).

## User Stories

1. As a bilingual macOS user, I want Oatmeal to transcribe my Spanish meeting in Spanish, so that the transcript reflects what was actually said.
2. As a bilingual macOS user, I want Oatmeal to detect the meeting language automatically, so that I do not have to configure it before every call.
3. As a bilingual macOS user, I want my Polish summary to be in Polish, so that the notes match the language of the conversation.
4. As a bilingual macOS user, I want action items to keep the speaker's original phrasing, so that I can search and recall them naturally.
5. As a bilingual macOS user, I want a language picker in Settings, so that I can lock in a single language when I know all my meetings will be in it.
6. As a bilingual macOS user, I want Settings to clearly say that auto-detect is slower than locking a language, so that I can make an informed choice.
7. As a bilingual macOS user, I want the note to show me which language was detected, so that I can verify the system understood the meeting correctly.
8. As a bilingual macOS user, I want to override the detected language and re-transcribe a note, so that a wrong auto-detect does not waste the recording.
9. As a bilingual macOS user, I want the re-transcribe to reuse the existing audio, so that I do not have to record the meeting again.
10. As a bilingual macOS user, I want the re-transcribe history to show which language was used in each attempt, so that I can keep track of what I tried.
11. As an English-only macOS user, I want my existing `.en` model and English-locked configuration to continue working unchanged, so that I do not regress on transcription latency.
12. As an English-only macOS user, I want the language picker to default to a sensible value for my system, so that I am not forced to make a decision before recording my first meeting.
13. As a new user, I want the language picker to surface a meaningful default based on my system locale, so that the app feels prepared.
14. As a multilingual user with multiple Whisper models installed, I want Oatmeal to automatically use my `.en` model for English meetings and my multilingual model for other languages, so that I get the best speed-quality trade-off without micromanaging.
15. As a user with only an English-only Whisper model, I want clear guidance when I try to enable auto-detect, so that I understand why it cannot work yet.
16. As a user trying to enable multilingual transcription, I want a curated list of recommended Whisper models in Settings with quality and size guidance per language, so that I can download the right one without external research.
17. As a privacy-conscious user, I want any model download to be initiated by an explicit click and to show what is being downloaded, so that nothing happens silently in the background.
18. As a privacy-conscious user, I want the source meeting recording to be deleted after transcription, so that the original high-fidelity audio does not linger on disk.
19. As a privacy-conscious user, I want a clear, accurate description of what audio Oatmeal retains after transcription, so that the privacy story matches the actual behavior.
20. As a user on a metered or slow connection, I want model downloads to be opt-in, so that Oatmeal never surprises me with hundreds of megabytes of traffic.
21. As a user without Whisper installed, I want Apple Speech to keep working as a fallback, so that I can still transcribe a meeting before completing the local setup.
22. As a user using the Apple Speech fallback, I want a clear hint that auto-detect requires Whisper, so that I understand why my Settings choice is being downgraded.
23. As a user using the Apple Speech fallback in a non-English system locale, I want the recognizer to run in my system language, so that the fallback is at least useful in my own language.
24. As a user without any LLM path configured, I want a clear "configure an LLM" error rather than empty or wrong-language notes, so that I am not confused about why the notes are missing.
25. As a user, I want the deterministic English-keyword fallback for note generation removed, so that Oatmeal does not silently produce empty notes for non-English meetings.
26. As a user, I want my recent meeting note to retain enough audio to support re-transcribe, so that I have a recovery path for the realistic auto-detect failure rate.
27. As a user, I want the retained per-note audio to be small enough that a year of meetings does not eat my disk, so that the retention change does not become its own problem.
28. As a user opening an old note where the audio is no longer available, I want the re-transcribe affordance to be hidden or clearly disabled, so that I do not get confused failures.
29. As a user who has just stopped recording, I want the post-meeting transcription to feel as fast as it did before this milestone, so that adding multilingual support did not make my common case slower.
30. As a user whose meetings are nearly always in English, I want auto-detect to be opt-in rather than a forced default, so that I am not paying the multilingual model cost without choosing it.
31. As a user, I want the language picker to support BCP 47 identifiers under the hood, so that the schema can support regional variants in the future.
32. As a user, I want the persisted detected language to survive app restart, so that opening an old note still shows what language it is in.
33. As a user, I want sorting, search, and filtering of notes to be schema-ready for language even if the UI does not yet expose it, so that future improvements do not require migrations.
34. As a remote-API user, I want frontier models (Claude, GPT) to summarize my non-English meetings reliably in the source language, so that quality is not bottlenecked by the local model.
35. As a local-MLX user with a small model, I want the prompt strategy to use translated system instructions for the most common languages, so that small models still produce notes in the right language even when their instruction-following is weak.
36. As a local-MLX user with a tail-language meeting, I want the system to fall back to English instructions plus an explicit "respond in X" directive, so that uncommon languages still get a usable summary.
37. As a developer maintaining this code, I want a single, pure language-policy module that decides which language and which model to use given the user's configuration, so that the routing logic is testable in isolation.
38. As a developer, I want a deterministic classifier that distinguishes English-only Whisper models from multilingual ones, so that auto-routing decisions do not depend on filename heuristics scattered across the codebase.
39. As a developer, I want the curated model catalog to live as data, so that adding or removing recommended models does not require rewriting selection logic.
40. As a developer, I want the audio retention policy to be encapsulated so that the rule "keep the normalized WAV, delete the originals" lives in one place and is testable.
41. As a developer, I want the whisper.cpp JSON parser to extract the detected language alongside segments, so that downstream consumers can persist it without parsing again.
42. As a developer, I want the prompt-template strategy to be encapsulated so that the choice between translated system prompts and English-plus-instruction is a single decision point.
43. As a developer, I want unit tests on the language policy, model classifier, retention coordinator, and prompt localizer modules, so that the central decisions of this milestone are protected from regression.
44. As a designer or future engineer, I want the data model to carry language at both the note level and the segment level, so that future code-switching work does not require a schema migration.
45. As a support engineer, I want the transcription history to record the language used for each attempt, so that user reports of "why is my transcript wrong" map to a concrete recorded decision.

## Implementation Decisions

### Scope and product behavior

- Per-meeting language detection is the unit of granularity. No per-segment code-switching support in the user-facing product. The data model is forward-compatible with code-switching but the UI treats a meeting as having one language.
- App chrome localization is out of scope for this milestone. No `Localizable.strings` or `.xcstrings` infrastructure work. The persona is users who are comfortable operating in English UI.
- Summaries are produced in the source language of the meeting, never translated to a user-preferred language. There is no settings option to override this in this milestone.
- Misdetection recovery is interactive: the note header surfaces the detected language with an override dropdown that triggers re-transcription against the retained audio.

### Language configuration and routing

- A single deep `LanguagePolicy` module owns the routing decision tree. Given the user's configured language preference (`auto` or a specific language), the active backend, and the discovered models, it returns the language argument to pass to the backend, the model to use, whether the configuration is degraded, and any blocking reason that should be surfaced.
- When the user's effective language is a specific language and a matching backend is available, the policy uses it directly. When the language is `auto`, the policy requires a multilingual Whisper model to be available, otherwise it returns a "blocked" decision with a user-facing reason.
- When the configured language is English (either explicitly or because the user has not chosen anything and their system locale is English) and an `.en` Whisper model is available, the policy prefers the `.en` model. This is the explicit "no regression for English users" guarantee.
- When the user has multiple Whisper models installed, the policy auto-routes: `.en` variants are preferred for English-locked configurations, multilingual variants for non-English or auto-detect configurations.
- Apple Speech is treated as a strictly degraded fallback. It cannot do auto-detect; when reached via fallback under an `auto` configuration, it runs in the user's system locale and the runtime status surfaces a `degraded` availability with a hint that auto-detect requires Whisper.

### Whisper model classification and curation

- A `WhisperModelClassifier` deep module classifies each discovered model into `(variant: englishOnly | multilingual, sizeTier: tiny | base | small | medium | large | other)` based on filename conventions. This replaces ad-hoc parsing inside `LocalModelInventory` and is the single source of truth for variant detection.
- `LocalModelInventory` is extended to expose the classification on each discovered model, but the discovery itself stays as it is today (filesystem-based, environment-overridable).
- A `CuratedModelCatalog` data structure lists known-good multilingual Whisper models, their download URLs, sizes, and per-language quality tiers (e.g. `small` is fine for major Romance languages, `medium` is recommended for Polish, Japanese, Arabic). The catalog is consumed by Settings to render recommendations.
- Settings adds a "Multilingual models" section with one-click download buttons for catalog entries. Downloads are explicit (no auto-download), show progress, and write to the existing managed models directory so the existing inventory picks them up.
- The exact list of catalog entries (initial set, download URLs) is left as a TBD to be resolved during implementation.

### Audio retention and re-transcribe

- The audio normalization output (16 kHz mono WAV) is moved from the per-job temp directory to a stable per-note location under the recordings directory. Whisper still consumes it the same way.
- The original capture artifacts (`.caf` microphone, `.mp4` system audio at 48 kHz) are deleted after successful normalization, replacing today's behavior of deleting them after successful note generation.
- The normalized WAV is retained for the lifetime of the note. Deletion is bound to note deletion, not to transcription success.
- An `AudioRetentionCoordinator` deep module owns the policy: given a note and its capture artifacts, it decides what to keep and what to delete on each lifecycle transition. The existing scattered cleanup in `MeetingCaptureEngine.clearExistingRecordingFiles` and `AppViewModel`'s post-success cleanup is centralized here.
- Re-transcribe is exposed on a note when (a) the note has a retained normalized WAV and (b) the user changes the language via the override dropdown. It runs the existing transcription pipeline against the retained WAV with the chosen language, and appends a new entry to the note's transcription history.

### Detected-language plumbing

- `WhisperJSONParser` is extended to extract the detected language from whisper.cpp's JSON output in addition to segments. The language is attached to the `TranscriptionJobResult`.
- `TranscriptionJobResult` gains a `detectedLanguage: String?` field. Apple Speech populates this with the locale it ran in.
- A `NoteLanguageInference` deep module derives a note's primary language from a list of segments with optional language tags, used when persisting a re-transcribed note.

### Data model

- `TranscriptSegment` gains an optional `language: String?` field (BCP 47). `nil` means "inherit the note's language." This is forward-compatible with future code-switching but the current pipeline does not populate per-segment values.
- `MeetingNote` gains an optional `language: String?` field (BCP 47), the primary language of the meeting.
- `NoteTranscriptionAttempt` gains an optional `language: String?` field, recording which language was used for each transcription attempt (including re-transcribes).
- All new fields are decoded with `decodeIfPresent` to preserve compatibility with existing on-disk notes.
- BCP 47 is the storage format. Whisper-sourced values are region-less (e.g. `"es"` rather than `"es-ES"`); Apple-Speech-sourced values include region. The format is a superset and consumers must handle both.

### Notes pipeline and prompts

- `DeterministicNoteGenerationService` is removed entirely. The English-keyword substring matching it relies on cannot be made multilingual without effectively rebuilding it, and it represents a small and shrinking fraction of the no-LLM-path use case.
- When neither a local MLX model nor a remote API is configured, the note generation pipeline surfaces a clear "configure an LLM in Settings" error rather than producing empty or English-keyword-grepped notes.
- The existing prompt templates in `OatmealServices.swift` continue to drive the LLM paths. They are no longer consumed by a deterministic fallback.
- A `PromptTemplateLocalizer` deep module encapsulates the hybrid prompt strategy. Given a template and a target language, it returns a localized system prompt for the top-N supported languages and an English-plus-`"respond in X"` instruction for tail languages. Structural keys (e.g. JSON schema field names like `action_items`) remain English regardless of language to keep parsing stable.
- The exact list of supported translated languages (top 5 vs top 10) is left as a TBD to be resolved during implementation.
- A remote API path remains a first-class option for note generation, alongside local MLX. Frontier models handle multilingual instruction-following reliably, so the hybrid prompt strategy primarily protects local MLX users.

### Settings UI

- Settings adds a "Transcription language" control with options for `Auto-detect` and an explicit list of languages.
- The control sits alongside the existing transcription backend and policy controls.
- A short, non-modal explanation states that auto-detect is slower than locking a language and requires a multilingual Whisper model.
- A "Multilingual models" subsection lists curated downloadable models with size and quality hints.
- Whether the language picker offers regional variants (`es-ES` vs `es-MX`) or only primary languages is left as a TBD; the BCP 47 schema lets us defer.

### Note-detail UI

- The note header surfaces the detected language with a dropdown override. Choosing a different language triggers the re-transcribe flow.
- When the note has no retained audio (legacy notes from before this milestone, or notes whose audio has been deleted), the re-transcribe affordance is hidden or clearly disabled with an explanation.
- The transcription history view continues to show prior attempts and additionally shows the language used for each.

### Out-of-scope-for-this-PRD TBDs to resolve during implementation

- The exact list of "supported languages" for translated system prompts (top 5 vs top 10) — depends on customer geography.
- The download source for the curated multilingual Whisper models (Hugging Face direct links vs a vendored CDN) — security and operational call.
- Whether the language picker offers regional variants (e.g. `es-ES`, `es-MX`) or only primary languages — BCP 47 schema lets us defer.

## Testing Decisions

A good test for this milestone tests external behavior at module boundaries, not implementation details. The deep modules introduced here have small, pure interfaces specifically so that they can be exercised by tabular input/output unit tests without spinning up a full pipeline. Tests should not assume a particular file layout, depend on real Whisper or ffmpeg binaries, or hit the network.

The following modules will be tested:

- `LanguagePolicy` — a tabular set of cases covering English-locked with `.en` model, English-locked with multilingual-only, auto-detect with multilingual model, auto-detect with `.en`-only models (blocked), specific non-English language with multilingual model, fallback into Apple Speech with each configuration, and the case of no models at all. Each case asserts the returned language argument, model selection, degradation flag, and blocking reason.
- `WhisperModelClassifier` — input filenames and expected `(variant, sizeTier)` outputs covering `.en` variants, multilingual variants, ambiguous filenames, and unknown size tiers.
- `AudioRetentionCoordinator` — given simulated capture artifact states and lifecycle events (normalization succeeded, note persisted, note deleted), assert which files are kept and which are deleted. Use an in-memory or temp-dir-backed `FileManager` shim.
- `WhisperJSONParser` extension — parse representative whisper.cpp JSON outputs and assert that the detected language is extracted alongside the segment list. Cover the case where whisper.cpp omits the language field.
- `NoteLanguageInference` — given lists of segments with various language tag distributions (all same, mixed, mostly-nil, all-nil), assert the inferred primary language.
- `PromptTemplateLocalizer` — for each supported translated language, assert that the returned system prompt is in that language and that structural keys remain English. For a tail language, assert that the English prompt with `"respond in X"` directive is returned.
- `CuratedModelCatalog` — recommendation function returns models in expected ranking for given target languages and device classes.

The transcription pipeline integration is exercised at a higher level:

- An end-to-end test against a deterministic fixture (the existing mock backend, extended to populate `detectedLanguage`) verifies that the language flows from `TranscriptionJobResult` into `MeetingNote.language` and `NoteTranscriptionAttempt.language`.
- A re-transcribe test verifies that overriding the language on a note with retained audio produces a new transcription attempt with the chosen language, appended to history.
- A negative test verifies that a note without retained audio reports re-transcribe as unavailable.

Prior art for these tests: the existing `Tests/OatmealCoreTests/` and `Tests/OatmealUITests/` directories contain similar tabular-style decision tests (`DetectionSettingsTests`, `MeetingDetectionLifecycleTests`) and mock-backed end-to-end tests (`SingleMeetingAIWorkspaceTestSupport`, `CaptureEngineTestDefaults`). The new tests should match those patterns.

UI tests for the Settings language picker, the note-detail "Detected" header, and the override-and-re-transcribe interaction follow the existing UI test conventions in `Tests/OatmealUITests/` and use the same workspace shell harness.

## Out of Scope

- App chrome localization. UI strings remain English. No `Localizable.strings` or `.xcstrings` infrastructure is introduced in this milestone.
- Right-to-left layout support. RTL languages (Arabic, Hebrew) will transcribe correctly but the surrounding UI is not RTL-aware.
- Locale-aware date and number formatting in the broader app. The hardcoded `"EEE, MMM d"` date format and other locale-naive formatters are not addressed here.
- Per-segment language detection in the user-visible UI. The data model carries an optional segment language for forward compatibility, but the pipeline populates it as `nil` and the UI does not surface it.
- True code-switching support (mixed-language audio in a single meeting). Whisper's quality on code-switched audio is the upstream limit and lifting it is a much larger project.
- Switching whisper.cpp from a CLI subprocess to a library or always-running daemon. Cold-load cost continues to be paid per-transcription; OS page cache amortizes it across consecutive meetings.
- Auto-downloading multilingual Whisper models. Downloads remain explicit per the local-first privacy posture.
- Translating the existing `.en` model away from its English-only specialization. Users who want multilingual must explicitly download a multilingual model.
- Translating the deterministic note fallback into other languages. The deterministic fallback is removed entirely rather than rewritten.
- Streaming/near-live multilingual transcription. The near-live transcription pipeline introduced in the prior milestone continues to operate as today; multilingual support here applies to the post-meeting batch transcription path.
- Translation of meeting summaries or transcripts into a different language than was spoken. Summaries are always in the source language.
- Settings options for "summary language" or "translate to my preferred language." May be revisited in a future milestone.
- Localized meeting-platform detection strings (e.g. translating the lowercase `"google meet"` substring match in `BrowserMeetingDetectionService`). Major platforms keep their English brand names globally and the bilingual-with-English persona will still recognize them.
