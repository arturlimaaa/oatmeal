## Problem Statement

Oatmeal now has a credible local-first meeting engine: it can detect likely meetings, capture microphone and system audio, recover from interruptions, transcribe locally, and generate enhanced notes. But once a meeting is done, the product still behaves more like a recorder with a generated recap than like an actual working surface for the meeting itself.

From the user’s perspective, the problem is:

- Oatmeal gives me a transcript and an enhanced note, but it does not yet let me work with that meeting conversationally
- if I want to ask a follow-up question, rewrite the recap into an email, or extract a clean task list, I still have to leave Oatmeal and paste content into another AI tool
- the note detail view lacks an obvious “AI workspace” for a single meeting, which makes Oatmeal feel narrower than Granola even when the capture engine is strong
- the current enhanced-note output is useful, but it is a fixed artifact rather than an interactive surface
- Oatmeal already stores transcript segments, raw notes, summaries, decisions, and action items, but it does not yet expose a focused user workflow that turns that meeting context into ongoing value

For Oatmeal to become a stronger competitor to Granola without exploding scope, the next step is not broad cross-meeting chat. It is a focused single-meeting AI workspace that lets the user ask questions, rewrite outputs, and jump back to grounded evidence inside one meeting.

## Solution

Implement a single-meeting AI workspace inside the main note experience.

From the user’s perspective:

- every meeting note gets a focused AI workspace
- I can ask questions about one meeting only
- Oatmeal answers using that meeting’s transcript, raw notes, enhanced note, and meeting metadata
- answers include source citations that let me jump back to the relevant transcript evidence
- Oatmeal offers one-tap actions for the most common jobs: recap email, decisions, action items, follow-up draft, and “what changed?”
- the AI workspace stays narrow on purpose: no multi-meeting reasoning, no global chat, no team assistant, no enterprise workflow complexity

This milestone should make Oatmeal feel meaningfully closer to Granola’s “meeting brain” value while staying disciplined about scope and while preserving the product’s local-first architecture.

## User Stories

1. As a meeting-heavy macOS user, I want an AI workspace inside a single note, so that I can keep working with the meeting after capture ends.
2. As a meeting-heavy macOS user, I want to ask natural-language questions about one meeting, so that I can recall details without rereading the whole transcript.
3. As a meeting-heavy macOS user, I want the AI workspace to stay scoped to one meeting only, so that I can trust that answers are not leaking across unrelated notes.
4. As a meeting-heavy macOS user, I want Oatmeal to use the transcript, raw notes, enhanced note, and meeting context together, so that answers are more useful than any one source alone.
5. As a meeting-heavy macOS user, I want the workspace to feel like part of the note, so that it does not seem like a bolted-on generic chat window.
6. As a meeting-heavy macOS user, I want to ask “What were the main decisions?” so that I can get a clean answer instantly.
7. As a meeting-heavy macOS user, I want to ask “What are the action items?” so that I can turn a meeting into next steps quickly.
8. As a meeting-heavy macOS user, I want to ask “What changed since last plan?” or similar recap questions, so that the AI workspace helps me synthesize movement.
9. As a meeting-heavy macOS user, I want to ask “What did we agree to send?” so that follow-up work is obvious.
10. As a meeting-heavy macOS user, I want to ask “What did the customer complain about?” so that I can pull out the critical signal from a long call.
11. As a meeting-heavy macOS user, I want one-tap prompt suggestions, so that I can use the feature without inventing prompts from scratch.
12. As a meeting-heavy macOS user, I want one-tap “Draft follow-up email,” so that I can move from meeting to action quickly.
13. As a meeting-heavy macOS user, I want one-tap “Summarize for Slack,” so that I can share outcomes without rewriting everything manually.
14. As a meeting-heavy macOS user, I want one-tap “Extract tasks,” so that operational follow-through is fast.
15. As a meeting-heavy macOS user, I want one-tap “Show decisions and risks,” so that I can separate commitment from open questions.
16. As a meeting-heavy macOS user, I want AI answers to cite their sources, so that I can verify that Oatmeal is grounded in the actual meeting.
17. As a meeting-heavy macOS user, I want to click a citation and jump to the relevant transcript span, so that I can inspect the original context immediately.
18. As a meeting-heavy macOS user, I want the AI workspace to admit uncertainty when the meeting does not contain enough evidence, so that I do not over-trust polished hallucinations.
19. As a meeting-heavy macOS user, I want Oatmeal to say when an answer came mostly from transcript versus raw notes, so that the evidence trail feels explainable.
20. As a meeting-heavy macOS user, I want the workspace to keep working even if enhanced-note generation is still incomplete, so that transcription completion is enough to unlock value.
21. As a meeting-heavy macOS user, I want the workspace to handle long meetings without dumping the entire transcript every time, so that answers stay responsive.
22. As a meeting-heavy macOS user, I want my conversation with the meeting to persist across relaunch, so that I can come back later without losing context.
23. As a meeting-heavy macOS user, I want to see my previous prompts and the assistant’s answers for that note, so that the workspace feels like a durable thread rather than a one-shot prompt box.
24. As a meeting-heavy macOS user, I want to retry a failed answer, so that transient runtime issues do not break the workflow.
25. As a meeting-heavy macOS user, I want to copy an answer easily, so that I can move it into email, Slack, docs, or tickets.
26. As a meeting-heavy macOS user, I want the AI workspace to stay in the main app, so that the recorder/controller remains lightweight and focused.
27. As a meeting-heavy macOS user, I want the AI workspace to use the current note title and calendar context, so that outputs feel tailored to the meeting instead of generic.
28. As a meeting-heavy macOS user, I want ad hoc meetings to work too, so that `Untitled Meeting` notes are still first-class once they have transcript content.
29. As a meeting-heavy macOS user, I want the AI workspace to help me rewrite content into different formats, so that Oatmeal becomes a working tool rather than a storage app.
30. As a meeting-heavy macOS user, I want Oatmeal to draft a recap in my likely voice and level of detail, so that I spend less time editing.
31. As a meeting-heavy macOS user, I want Oatmeal to extract tasks with likely owners when the meeting makes them clear, so that action items are more operationally useful.
32. As a meeting-heavy macOS user, I want Oatmeal to separate confirmed decisions from tentative discussion, so that I do not confuse speculation with commitments.
33. As a meeting-heavy macOS user, I want Oatmeal to highlight open questions and risks, so that the note is not biased toward false certainty.
34. As a meeting-heavy macOS user, I want the workspace to stay fast and local-first when possible, so that it aligns with Oatmeal’s privacy story.
35. As a meeting-heavy macOS user, I want the product to degrade gracefully when the richer local model runtime is unavailable, so that the feature still feels usable.
36. As a meeting-heavy macOS user, I want answer quality to be better than keyword search alone, so that the AI workspace earns its place in the UI.
37. As a meeting-heavy macOS user, I want answers to remain bounded to the meeting instead of acting like a general-purpose chatbot, so that the product stays trustworthy.
38. As a meeting-heavy macOS user, I want the workspace to be obviously unavailable or limited before transcription is ready, so that the state is understandable.
39. As a meeting-heavy macOS user, I want the workspace to explain when it is still preparing the note context, so that I know whether to wait or retry.
40. As a meeting-heavy macOS user, I want the meeting AI workspace to feel like the first serious intelligence layer in Oatmeal, so that the product gap with Granola shrinks in a visible way.
41. As a product engineer, I want a deep context-building module for one meeting, so that transcript, summary, raw notes, and metadata are assembled consistently everywhere.
42. As a product engineer, I want the AI answer pipeline to use explicit grounding and citation extraction, so that behavior is testable and not just prompt magic.
43. As a product engineer, I want the single-meeting assistant to avoid requiring a vector database in v1, so that scope stays narrow and iteration stays fast.
44. As a product engineer, I want the assistant to use transcript-segment identifiers as the canonical grounding anchor when possible, so that UI jump-to-source behavior remains deterministic.
45. As a product engineer, I want one persisted thread model per meeting, so that chat history, retries, and relaunch behavior are coherent.
46. As a product engineer, I want assistant actions like “recap email” and “extract tasks” to be recipes over the same meeting context rather than bespoke one-off features, so that new workspace actions are cheap to add.
47. As a product engineer, I want the workspace to use the existing local ML/runtime seams where possible, so that Oatmeal does not fork its AI architecture into unrelated paths.
48. As a product engineer, I want a clear fallback path when the richer assistant runtime is unavailable, so that the app remains functional on more machines.
49. As a product engineer, I want the workspace UI state to be isolated from the note model complexity, so that the view layer is not forced to interpret processing, grounding, and thread state directly.
50. As a product engineer, I want good tests around context assembly, answer grounding, citation mapping, and action workflows, so that the feature can evolve without losing trust.

## Implementation Decisions

- This milestone covers `single-meeting AI workspace` only. It does not introduce cross-meeting chat, global search chat, team chat, or folder/workspace intelligence.
- The workspace should live in the main note experience, not in the floating recorder or menu bar. The lightweight recorder remains focused on live meeting control.
- The workspace should be unlocked per note once sufficient meeting material exists. In practice, that means:
  - available when a note has a completed or recovered transcript
  - optionally available in a reduced mode when only an enhanced note exists, but transcript-backed behavior is the primary path
- Oatmeal should treat the meeting as the hard scope boundary. Every answer must be grounded only in:
  - that note’s transcript segments
  - that note’s raw notes
  - that note’s enhanced note
  - that note’s calendar metadata and title
- The milestone should introduce a deep `SingleMeetingContextBuilder` module that assembles the canonical assistant context for one note. It should be responsible for:
  - normalizing transcript segments
  - including raw notes and enhanced-note structure
  - packaging meeting metadata
  - selecting the most relevant excerpts for long meetings
- The milestone should introduce a deep `MeetingAssistantService` module that takes a user prompt or predefined action plus the assembled meeting context and returns:
  - assistant response text
  - optional structured payloads for actions like task extraction or email drafting
  - source anchors/citations
  - runtime metadata and failure state
- The assistant path should remain local-first and should reuse existing runtime patterns where practical. It is acceptable for v1 to define a dedicated assistant runtime seam even if it initially reuses the summary/runtime environment under the hood.
- The milestone should introduce a persisted `MeetingAssistantThread` or equivalent thread model at the note level. It should store:
  - user prompts
  - assistant responses
  - timestamps
  - response state such as running/failed/completed
  - source citations / source anchors
- The workspace should not require a vector database in v1. Single-meeting scope is narrow enough that a deterministic local retrieval/ranking strategy over transcript segments, raw notes, and summary sections is the better tradeoff.
- The milestone should introduce a `MeetingAssistantCitationResolver` or equivalent module that maps assistant citations back to transcript segment identifiers and other note-local anchors. Transcript spans should be the preferred jump target.
- The milestone should ship a small set of first-class actions instead of generic open-ended chat alone. At minimum:
  - ask arbitrary question
  - draft follow-up email
  - summarize for Slack
  - extract action items
  - show decisions and risks
- These actions should be implemented as recipes over the same single-meeting context, not as separate bespoke subsystems.
- The UI should expose:
  - a single-meeting workspace panel or tab within note detail
  - suggested prompts/actions
  - a persistent thread for that note
  - inline loading, error, and retry states
  - clickable citations into transcript context
- The workspace should preserve Oatmeal’s grounded-product stance. The assistant should prefer:
  - explicit uncertainty when evidence is weak
  - answering from cited excerpts instead of pure freeform synthesis
  - refusing to imply confidence where the note context is incomplete
- The milestone should preserve solo-user scope. There is no shared chat thread, no workspace collaboration, and no web sharing of assistant threads in this phase.
- The milestone should not broaden into full cross-note search or RAG. If a later milestone adds multi-meeting intelligence, it should build on the single-meeting assistant patterns established here rather than skipping directly to broad retrieval complexity.

## Testing Decisions

- Good tests for this milestone validate externally visible behavior:
  - whether a note with sufficient transcript content enables the workspace
  - whether a prompt or recipe produces a grounded answer
  - whether citations map back to valid transcript anchors
  - whether retries, failures, and relaunch persistence behave correctly
- Tests should focus on grounded outputs and user-visible state transitions rather than brittle assertions on exact prompt wording or internal runtime prompts.
- The `SingleMeetingContextBuilder` should be tested with:
  - short notes
  - long transcripts
  - notes with raw notes but sparse transcript
  - notes with enhanced note available versus not yet available
- The `MeetingAssistantService` should be tested for:
  - answer generation on one meeting only
  - action recipes such as email recap and task extraction
  - graceful fallback when richer runtime paths are unavailable
  - uncertainty behavior when evidence is weak
- The citation resolver should be tested for:
  - mapping answer citations back to valid transcript segment IDs
  - rejecting or degrading invalid citations safely
  - supporting deterministic jump-to-source behavior
- The note-level thread persistence should be tested for:
  - relaunch recovery
  - retry behavior
  - preserving completed and failed turns in order
- App-level tests should verify:
  - workspace availability gating based on note processing state
  - clicking a citation routes the user to the relevant transcript context
  - predefined actions and freeform prompts both use the same meeting-scoped thread behavior
- Prior art already exists in the repo for:
  - persistence and relaunch recovery
  - note-processing lifecycle tests
  - session-controller routing/state adapter tests
  - deterministic local runtime selection tests
- This milestone should extend those behavioral patterns rather than introducing fragile pixel-level UI tests or implementation-detail assertions.

## Out of Scope

- cross-meeting chat
- global “ask all notes” intelligence
- team/shared assistant threads
- workspace or folder AI
- broad integrations
- web chat surfaces
- Windows or iPhone AI workspace parity
- diarization improvements
- major recorder/controller redesign
- remote-provider-first architecture
- a full generic chatbot persona unrelated to the meeting
