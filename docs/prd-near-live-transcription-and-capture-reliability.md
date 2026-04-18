## Problem Statement

Oatmeal can already capture meetings locally, persist artifacts, and transcribe recordings after capture stops, but it does not yet behave like a dependable always-on meeting engine. For a user in a real meeting, that means the app still feels closer to a strong post-processing prototype than to a trustworthy daily driver. The current system records microphone-only quick notes and mixed system-audio meeting artifacts, then runs transcription after the meeting ends. That leaves important product gaps:

- users cannot benefit from transcription progress during the meeting
- long meetings push all transcription latency to the end of the session
- recovery is oriented around post-capture work, not an actively progressing live pipeline
- capture reliability under real-world conditions such as relaunch, device changes, and backlog pressure is not yet a first-class product surface

For Oatmeal to become a credible local-first alternative to Granola or Jamie on macOS, the engine has to feel invisible and dependable. The user should feel that Oatmeal is continuously keeping up in the background, preserving the meeting even when something goes wrong, and turning that meeting into usable notes with minimal waiting after the meeting ends.

## Solution

Implement a near-live, background transcription and reliability milestone for macOS that upgrades Oatmeal from a stop-then-transcribe flow into a chunked live-processing system.

From the user’s perspective:

- Oatmeal records microphone plus system audio for scheduled meetings
- Oatmeal transcribes in the background while the meeting is still happening
- the user can open a transcript panel during the meeting if they want, but Oatmeal does not force the transcript into the foreground
- if transcription falls behind, Oatmeal keeps recording and catches up automatically
- if the app is quit or crashes, Oatmeal resumes from saved capture artifacts on relaunch with minimal user intervention
- if audio devices change mid-meeting, Oatmeal preserves the session whenever possible instead of silently failing
- when the meeting ends, there is far less post-meeting wait because most of the work has already been done

This milestone explicitly optimizes for:

- never losing the recording
- strong transcription accuracy
- low enough latency to feel near-live without destabilizing capture

This milestone does not promise full diarization, named speakers, or the final polished recorder widget. It creates the engine that later UI milestones will sit on top of.

## User Stories

1. As a meeting-heavy macOS user, I want Oatmeal to keep recording even if transcription work falls behind, so that I never lose the meeting.
2. As a meeting-heavy macOS user, I want Oatmeal to transcribe in the background during a meeting, so that I wait less after the meeting ends.
3. As a meeting-heavy macOS user, I want Oatmeal to capture both my microphone and meeting audio, so that the transcript reflects the whole conversation.
4. As a meeting-heavy macOS user, I want background transcription to happen without interrupting my work, so that Oatmeal feels invisible during meetings.
5. As a meeting-heavy macOS user, I want to optionally open a transcript panel mid-meeting, so that I can check what Oatmeal has heard without leaving the session.
6. As a meeting-heavy macOS user, I want Oatmeal to continue producing transcript chunks while the app remains in the background, so that I do not need to babysit it.
7. As a meeting-heavy macOS user, I want Oatmeal to preserve local artifacts before doing expensive processing, so that capture safety is prioritized over convenience.
8. As a meeting-heavy macOS user, I want Oatmeal to catch up automatically after temporary slowdowns, so that a short performance dip does not ruin the meeting.
9. As a meeting-heavy macOS user, I want Oatmeal to recover unfinished live transcription after relaunch, so that a crash does not force me to restart from zero.
10. As a meeting-heavy macOS user, I want Oatmeal to reopen with my in-progress meeting state restored as much as possible, so that the app feels resilient.
11. As a meeting-heavy macOS user, I want Oatmeal to keep partial transcript progress durably on disk, so that work completed during the meeting is not lost.
12. As a meeting-heavy macOS user, I want Oatmeal to clearly indicate when live transcription is healthy, catching up, or delayed, so that I understand the current session state.
13. As a meeting-heavy macOS user, I want transcript updates to appear incrementally rather than only at the end, so that the transcript panel feels alive.
14. As a meeting-heavy macOS user, I want Oatmeal to avoid burning excessive resources for negligible improvement, so that the app stays usable during long meetings.
15. As a meeting-heavy macOS user, I want Oatmeal to prefer reliability over aggressive live latency when the system is under pressure, so that it degrades gracefully.
16. As a meeting-heavy macOS user, I want Oatmeal to support long meetings without runaway memory growth, so that it remains stable over time.
17. As a meeting-heavy macOS user, I want Oatmeal to handle scheduled meetings and quick notes through one coherent live-transcription architecture, so that behavior is predictable.
18. As a meeting-heavy macOS user, I want transcription chunks to preserve timestamps, so that later summaries and source inspection remain trustworthy.
19. As a meeting-heavy macOS user, I want transcript chunks to merge into one coherent transcript after the meeting, so that the final note looks clean.
20. As a meeting-heavy macOS user, I want Oatmeal to avoid duplicating or dropping transcript text when chunks overlap, so that the transcript stays readable.
21. As a meeting-heavy macOS user, I want the final enhanced note pipeline to reuse the near-live transcript, so that post-meeting generation feels fast.
22. As a meeting-heavy macOS user, I want Oatmeal to keep working if my microphone device changes mid-meeting, so that routine hardware changes do not break capture.
23. As a meeting-heavy macOS user, I want Oatmeal to react gracefully if my headphones disconnect or the output device changes, so that real meetings do not derail the session.
24. As a meeting-heavy macOS user, I want Oatmeal to surface actionable recovery guidance if device switching cannot be handled automatically, so that I know what to do next.
25. As a meeting-heavy macOS user, I want Oatmeal to retain enough metadata about live capture and live transcription state, so that relaunch recovery can resume intelligently.
26. As a meeting-heavy macOS user, I want Oatmeal to preserve the original recording even when a transcription chunk fails, so that the system can retry later.
27. As a meeting-heavy macOS user, I want Oatmeal to retry failed or missing chunk work after the meeting ends, so that temporary failures do not become permanent data loss.
28. As a meeting-heavy macOS user, I want Oatmeal to keep the transcript panel optional, so that the app does not distract me during meetings.
29. As a meeting-heavy macOS user, I want Oatmeal to keep my local-first privacy posture while improving live behavior, so that the product remains differentiated.
30. As a meeting-heavy macOS user, I want Apple Silicon to be the explicit optimization target for this milestone, so that local performance expectations remain realistic.
31. As a product engineer, I want one clear capture coordinator for live sessions, so that session lifecycle bugs are easier to reason about.
32. As a product engineer, I want live transcription to run through a dedicated chunk coordinator instead of ad hoc calls, so that queueing and retries are testable in isolation.
33. As a product engineer, I want chunk processing to persist durable checkpoints, so that relaunch recovery does not rely on in-memory state.
34. As a product engineer, I want capture artifacts and transcript chunks to have explicit lifecycle rules, so that cleanup does not race successful processing.
35. As a product engineer, I want device-change handling to be modeled explicitly in session state, so that UI and recovery logic consume one source of truth.
36. As a product engineer, I want observability around backlog depth, chunk latency, and recovery events, so that we can tune the live pipeline empirically.
37. As a product engineer, I want acceptance tests for relaunch recovery and chunk merging, so that the most important reliability claims stay protected.
38. As a designer or future engineer, I want the transcript panel state to already exist before the floating recorder milestone, so that later UI work can reuse a stable engine.
39. As a support/debugging engineer, I want persisted status for “live”, “catching up”, “delayed”, and “recovered”, so that user reports map to concrete system states.
40. As a support/debugging engineer, I want the app to distinguish capture failure from transcription delay, so that troubleshooting is precise.
41. As a user with a very short meeting, I want Oatmeal to still preserve the recording and whatever transcript progress exists, so that short sessions are not treated as broken.
42. As a user with a long meeting, I want Oatmeal to roll transcription forward incrementally, so that the system does not defer all work to the end.
43. As a user who never opens the transcript panel, I want this milestone to still improve my experience through faster final notes and stronger reliability.
44. As a user who does open the transcript panel, I want the panel to show stable chunked progress instead of noisy reflows, so that it remains readable.
45. As a user, I want Oatmeal to feel magical after a relaunch by continuing where it left off, so that failures feel recoverable rather than catastrophic.

## Implementation Decisions

- This PRD covers one milestone only: near-live background transcription plus stronger capture reliability. The menu-bar app and floating recorder/controller are intentionally deferred until the engine is more trustworthy.
- The milestone targets Apple Silicon Macs only. Intel support is not a delivery target for this phase.
- The live transcription model is chunked background processing rather than word-by-word streaming. The system should produce transcript updates continuously during the meeting while retaining enough buffering to protect accuracy and stability.
- The user-visible experience is transcript-optional. Oatmeal will keep a transcript panel available during the meeting, but the primary behavior remains background-first.
- Mixed meeting capture should use the smoothest and most optimizable artifact strategy available on macOS. The system may use a single mixed artifact rather than separate mic/system stems if that yields better reliability and simpler performance behavior.
- The system prioritizes recording durability over live latency. If transcription falls behind, Oatmeal must keep recording and catch up later automatically.
- Chunked live transcription should feed the same durable transcript model used by post-meeting note generation, rather than creating a separate “temporary live transcript” data path.
- Persisted state must expand from post-capture recovery to live-session recovery. The app should be able to resume unfinished transcription work from saved artifacts and saved chunk checkpoints after relaunch.
- The engine should distinguish at least these states: capture active, transcription healthy, transcription catching up, transcription delayed, recovered after relaunch, capture failed, transcription failed.
- Mid-meeting device changes are in scope. The session coordinator must respond to microphone and output-device changes with automatic reconfiguration when feasible, and actionable degraded-state handling otherwise.
- True diarization is explicitly out of scope for this milestone. The system may preserve coarse speaker metadata if it falls out naturally, but there is no commitment to named speakers or stable speaker clustering.
- The main deep modules for this milestone are:
  - a capture session coordinator that owns live session lifecycle, active devices, artifact policy, and error transitions
  - a chunked transcription coordinator that decides when to cut work units, enqueue them, merge results, and expose session progress
  - a transcription persistence/recovery layer that stores chunk progress, replay state, and unfinished work durably
  - an artifact store and cleanup policy that separates “safe to delete” from “must retain for recovery”
  - a transcript presentation adapter that feeds the optional in-meeting transcript panel without coupling UI to engine internals
- The existing transcription runtime selection and whisper.cpp pipeline should be reused rather than replaced. This milestone changes orchestration and durability more than backend selection.
- The existing post-capture processing flow should become the fallback/catch-up path for missed live chunks and final reconciliation instead of remaining the only path.
- The final enhanced-note stage should consume the reconciled transcript produced by the live pipeline so post-meeting note generation becomes much faster by default.
- The PRD should include explicit observability requirements for chunk latency, backlog depth, recovery frequency, and failure types, because performance tuning without these signals will be guesswork.
- Support targets should be framed as experience and acceptance targets rather than a broad machine matrix. The app should remain responsive during normal 30 to 60 minute meetings on common Apple Silicon laptops.

## Testing Decisions

- Good tests for this milestone validate externally observable behavior: chunk progress, merged transcript continuity, recovery after relaunch, correct fallback to catch-up mode, and preserved artifacts after failures. They should avoid coupling to private timing implementation details unless timing is itself part of the contract.
- The capture session coordinator should be tested with simulated lifecycle events, interruptions, and device changes.
- The chunked transcription coordinator should be tested for chunk scheduling, backlog growth, catch-up behavior, merge correctness, and duplicate/drop prevention.
- The transcription persistence/recovery layer should be tested for relaunch behavior, checkpoint replay, partial-progress durability, and safe retries after failure.
- The artifact store/cleanup policy should be tested for retention behavior before completion, after successful completion, and after failed completion.
- The transcript presentation adapter should be tested for stable incremental updates and state transitions exposed to the UI.
- App-level tests should verify that a relaunched app resumes unfinished live transcription work and clears recovery states once reconciliation completes.
- Performance-oriented tests should focus on chunk latency, backlog accumulation, and responsiveness under longer recordings, but should assert behavior envelopes rather than fragile exact timings where possible.
- Prior art in the codebase already exists for persisted recovery flows, transcription runtime planning, and app-level async processing behavior. This milestone should extend those testing patterns rather than invent a new style.

## Out of Scope

- menu-bar app behavior
- floating recorder widget
- expanded live meeting controller UI beyond the optional transcript panel
- true diarization or named-speaker attribution
- team collaboration, sharing, chat, or integrations
- iPhone, Windows, or web support
- full device-matrix optimization beyond Apple Silicon
- broad enterprise policy work
- a complete redesign of the summary generation pipeline
- replacing whisper.cpp with a different ASR backend as part of this milestone
