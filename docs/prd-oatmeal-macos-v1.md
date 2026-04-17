# Oatmeal PRD: macOS Native AI Meeting Notes v1

## Document Status

Draft

## Product Summary

Oatmeal is a macOS-native AI meeting notes app inspired by the core workflow popularized by Granola: capture meeting audio locally without adding a meeting bot, let the user jot lightweight notes during the conversation, and generate high-quality notes immediately afterward using the transcript, the user's notes, and calendar context.

This PRD defines a focused v1 that is intentionally narrower than Granola's full product surface. The release target is a polished single-platform macOS app for individuals and small teams, with the minimum backend needed to sync notes, generate summaries, share notes by link, and organize notes into folders.

## Assumptions

- Oatmeal is greenfield and does not need to preserve any existing architecture.
- v1 is macOS-only. iPhone, Windows, and browser capture are out of scope.
- v1 should be native to macOS in both feel and implementation, not a wrapped web app.
- The product should replicate the workflow category, not copy Granola's branding, copywriting, or exact UI.
- Oatmeal should avoid visible meeting bots and instead capture audio locally on the user's Mac.
- Calendar-driven workflows are central to the product, but ad hoc notes must also be supported.
- v1 may rely on third-party AI and transcription providers, but customer data must not be used to train third-party models.
- Enterprise controls, regulated-industry compliance, and full org administration are not required for v1.

## Problem Statement

Professionals in frequent meetings need accurate notes, decisions, and action items, but existing workflows force an unpleasant tradeoff. They either take notes manually and lose attention during the conversation, or they invite a meeting bot that changes the social dynamics of the call and still produces generic summaries that require cleanup.

Users want a meeting companion that feels invisible during the meeting and useful after it. They want to type a few cues while the discussion is happening, trust that the application will capture the conversation from their Mac, and receive clear, structured notes that are easy to search, organize, refine, and share.

For Oatmeal specifically, the problem is not "how do we transcribe meetings?" but "how do we help macOS users remember, reuse, and operationalize meeting context with minimal in-meeting effort?"

## Solution

Oatmeal will be a macOS-native AI note-taking application built around five core behaviors:

- Show upcoming meetings from the user's connected calendar and let the user launch a note from that meeting card.
- Capture microphone and system audio locally on macOS without joining the call as a visible participant.
- Provide a lightweight native note editor for raw notes taken during the meeting.
- Generate AI-enhanced notes after the meeting by combining transcript, user notes, and calendar metadata.
- Let the user organize, search, chat with, and share their notes after the meeting.

The v1 product experience should feel fast, quiet, and opinionated. It should help the user stay present during the meeting, then shift into a post-meeting workspace for editing, recall, and follow-up.

## Goals

- Build a high-quality macOS-native note-taking experience that feels credible beside first-party Apple productivity apps.
- Make Oatmeal useful on day one for a single user with no team setup.
- Produce meeting notes that are materially better than transcript dumps and good enough to share without major rewriting.
- Support the common workflows of product, engineering, design, founder, recruiting, and customer conversations.
- Preserve the social advantage of local capture by avoiding bot joins.
- Establish an architecture that can later support Windows, iPhone, workspace admin controls, and richer integrations.

## Success Metrics

- At least 70% of meetings with completed capture result in an enhanced note being viewed after generation.
- At least 50% of generated notes are edited, copied, shared, or used in chat within 24 hours.
- Median time from meeting end to first readable enhanced note is under 20 seconds for standard 30-60 minute meetings.
- At least 60% of weekly active users create notes for 3 or more meetings per week by week 4.
- Less than 3% of completed captures fail to produce a usable note because of transcription, permission, or sync issues.
- At least 40% of weekly active users use folders, templates, or chat after their first week, proving the product is more than a one-shot summarizer.

## Product Principles

- Native first: the product should behave like a serious Mac app, with strong keyboard support, predictable windowing, and excellent offline-tolerant state handling.
- Low ceremony capture: starting a note should be faster than opening a blank document.
- User-guided AI: raw notes should steer the final summary instead of being discarded.
- Summary before transcript: the default experience should emphasize useful notes, not raw transcript sprawl.
- Quiet collaboration: sharing should be available, but the product should remain primarily valuable even for a solo user.
- Tight scope: v1 should be narrow enough to ship with high polish and low reliability risk.

## Target Users

- Individual knowledge workers with 5-20 meetings per week.
- Founders and leaders who need reusable meeting memory.
- Product managers, designers, researchers, engineers, recruiters, and sales-adjacent users who need structured follow-up.
- Small teams that want to share selected notes and maintain a lightweight meeting archive.

## Non-Goals

- Replacing dedicated CRM systems, project managers, or full knowledge base tools.
- Fully autonomous action-taking across external systems.
- Enterprise security administration, SSO, SCIM, DLP, or legal hold.
- Mobile meeting capture.
- Joining meetings as a bot.
- Perfect speaker diarization for multi-speaker calls.
- Bulk import and backfill of historical audio files.

## v1 Scope

- Native macOS app using Apple platform capabilities for audio permissions, notifications, calendar access, and local application behavior.
- Google Calendar and Microsoft calendar connection.
- Upcoming meeting list and meeting reminder workflow.
- Ad hoc note creation outside calendar events.
- Real-time capture of microphone and system audio on macOS.
- Transcript view during and after the meeting.
- Raw note editor during capture.
- AI-enhanced note generation after capture completes.
- Built-in note templates and user-defined templates.
- Search across notes.
- Folders for organization.
- Basic chat over a single note and user-selected multiple notes.
- Share note by link with read-only web view.
- User settings for preferences, permissions guidance, and data/privacy controls.

## Out of Scope for v1

- iPhone, iPad, Windows, and Android clients.
- Browser-based recording or summarization flows.
- Team-wide workspace administration beyond lightweight invite/billing concepts.
- Folder-level automation to Slack, Notion, or CRM.
- Enterprise API or public developer API.
- Rich meeting analytics dashboards.
- Automatic attendee-sharing after every meeting.
- Inbound and outbound phone capture outside what is possible from the Mac itself.
- Full people/company CRM graph.
- Fine-grained transcript retention rules.

## User Experience Overview

### Primary End-to-End Flow

1. User installs Oatmeal on macOS.
2. User signs in and connects Google or Microsoft calendar.
3. Oatmeal requests microphone, system-audio, notifications, and calendar permissions.
4. User sees upcoming meetings in a native home screen.
5. User clicks a meeting card or creates a Quick Note.
6. Oatmeal opens a meeting note window and begins or prepares for transcription.
7. During the meeting, the user writes lightweight notes while Oatmeal captures transcript data.
8. When the meeting ends or the user stops capture, Oatmeal generates enhanced notes.
9. User reviews, edits, regenerates with another template, searches the transcript, or asks chat follow-up questions.
10. User places the note into folders or shares it by link.

### Key UX Constraints

- The capture workflow must feel trustworthy and legible. The user should always know whether Oatmeal is listening.
- Meeting notes must open quickly and preserve in-progress text even during connectivity interruptions.
- The transcript should remain secondary in hierarchy to the enhanced note.
- The app should feel functional even before the user configures templates or sharing.

## Functional Requirements

### 1. Account and Onboarding

- Users must be able to create an account with Google or Microsoft.
- Users must be able to connect at least one calendar during onboarding.
- The app must explain why each permission is needed before the system prompt appears.
- The app must support onboarding completion even if a user skips one or more permissions, but the UI must clearly explain resulting limitations.
- The app must present a short privacy summary explaining local audio capture, transcript storage, and model usage.

### 2. Home and Upcoming Meetings

- The home screen must show upcoming meetings from connected calendars.
- The home screen must distinguish between scheduled meetings and ad hoc notes.
- The app must allow the user to open a meeting note before the meeting starts.
- The app should suppress clearly irrelevant calendar items such as all-day placeholders, declined events, and focus blocks when possible.
- The app should support a configurable meeting reminder notification shortly before the meeting.

### 3. Meeting Note Creation

- Users must be able to create a note from a calendar event.
- Users must be able to create a Quick Note without a calendar event.
- New notes must include metadata when available: title, start time, attendees, conferencing link, and calendar source.
- The app must persist note drafts locally before upload or generation succeeds.

### 4. Audio Capture and Transcription

- Oatmeal must capture both microphone and system audio on macOS.
- Oatmeal must never join a meeting as a visible bot participant.
- Oatmeal must show clear capture state: ready, capturing, paused, failed, complete.
- Users must be able to stop capture manually.
- If capture permissions are missing, Oatmeal must show a recovery path.
- Transcript text should stream into the note view during capture or shortly after receipt from the provider.
- Oatmeal should support meetings on any conferencing platform because it operates at the Mac audio layer.
- Oatmeal should also support in-person meetings captured through the Mac microphone.

### 5. Raw Notes Editor

- The note editor must be available before, during, and after capture.
- The editor must support fast plain text entry with lightweight markdown-like structure.
- The editor must autosave continuously.
- The editor should preserve headings and bullets so they can influence final note structure.
- The editor should support keyboard-first use and standard macOS text interactions.

### 6. Enhanced Note Generation

- Oatmeal must generate enhanced notes after capture ends, using transcript, raw notes, and meeting metadata.
- Enhanced notes must include at least: summary, key discussion points, decisions, risks or open questions, and action items when the meeting contains them.
- Users must be able to edit enhanced notes directly.
- Users must be able to regenerate notes using the same transcript and raw notes.
- Users must be able to switch templates and regenerate without losing the original raw transcript.
- The app should visually distinguish user-authored raw notes from AI-authored enhanced content where useful.

### 7. Templates

- Oatmeal must provide a default automatic template that works for general-purpose meetings.
- Oatmeal must provide several built-in templates, such as 1:1, stand-up, interview, customer call, and project review.
- Users must be able to create and save custom templates.
- Users must be able to set a default template or choose one per note.
- Template application must affect note structure and emphasis, not transcript fidelity.

### 8. Transcript and Source Inspection

- Users must be able to read the transcript after capture.
- Users must be able to search within the transcript.
- Users must be able to copy transcript text.
- The product should support light source inspection so the user can understand why a generated point appears in the enhanced note.
- The transcript must remain available even if the user heavily edits the enhanced note.

### 9. Search and Retrieval

- Users must be able to search across note titles, note bodies, and transcript text.
- Search results must show enough snippet context for users to identify the right meeting quickly.
- Search should support basic metadata filters such as date range and folder.
- Search must be fast enough to feel local even if backed by remote indexing.

### 10. Chat Over Notes

- Users must be able to ask questions about a single note.
- Users must be able to select multiple notes and ask cross-note questions.
- Chat responses should be grounded in the available notes and transcripts, not generic prose.
- Chat should be able to perform common tasks such as summarization, extraction of action items, and drafting follow-up messages.
- Chat history may be note-scoped or user-scoped, but it must not be accidentally exposed via note sharing.

### 11. Organization

- Users must be able to create folders.
- Users must be able to move notes into folders.
- Each note will belong to at most one folder in v1.
- Folders must be searchable and visible in primary navigation.
- Users should be able to pin or favorite important folders.

### 12. Sharing

- Users must be able to share a note by link.
- Shared notes must render in a browser as readable formatted notes.
- Shared links must respect one of at least three privacy settings: private, anyone with link, or only signed-in users from my team domain.
- Shared viewers should see enhanced notes and limited metadata.
- v1 shared viewers should not have access to raw transcript unless explicitly enabled in product settings.
- Link access changes must take effect quickly and predictably.

### 13. Settings and Preferences

- Users must be able to manage connected calendars.
- Users must be able to manage notification timing.
- Users must be able to manage default templates and sharing defaults.
- Users must be able to review privacy settings, delete notes, and delete account data.
- Users must be able to review permission status and receive repair guidance.

### 14. Reliability and Sync

- Notes must survive app restarts, machine sleep, transient network failures, and provider timeouts.
- In-progress meetings must be recoverable after a crash when technically possible.
- Local state must sync to backend once connectivity returns.
- The app must preserve the transcript and raw notes even if enhanced note generation fails, so regeneration can be retried later.

## User Stories

1. As a frequent meeting participant, I want to open Oatmeal from an upcoming meeting card, so that I can start note-taking with one click.
2. As a macOS user, I want Oatmeal to feel like a native Mac app, so that it is fast, keyboard-friendly, and trustworthy during work.
3. As a user in a Zoom, Meet, or Teams call, I want Oatmeal to capture audio from my Mac without adding a bot, so that the meeting dynamic stays unchanged.
4. As a user in an in-person conversation, I want Oatmeal to capture notes from my Mac microphone, so that I can use the same workflow off-video as well.
5. As a user, I want to create a Quick Note without a calendar event, so that I can capture ad hoc conversations and thoughts.
6. As a user, I want to start typing raw notes before the meeting begins, so that I can capture an agenda and pre-meeting context.
7. As a user, I want Oatmeal to autosave my raw notes continuously, so that I never lose context during a meeting.
8. As a user, I want simple headings and bullets in my raw notes to influence the final summary, so that the AI output matches what I cared about.
9. As a user, I want clear visual confirmation when Oatmeal is actively capturing, so that I know whether the meeting is being recorded for transcription.
10. As a privacy-conscious user, I want Oatmeal to explain what data it stores and why, so that I can decide whether to trust it.
11. As a new user, I want onboarding to work even if I skip some permissions, so that I can explore the product before fully committing.
12. As a user, I want upcoming meetings from my calendar to appear automatically, so that I do not have to create every note manually.
13. As a user, I want Oatmeal to ignore obviously irrelevant calendar blocks, so that my home screen stays focused on real meetings.
14. As a user, I want to receive a reminder shortly before a meeting, so that I remember to open my note at the right time.
15. As a user, I want a transcript to appear while or shortly after the meeting is happening, so that I can trust the capture is working.
16. As a user, I want Oatmeal to generate enhanced notes after the meeting ends, so that I do not need to rewrite my notes from scratch.
17. As a user, I want the enhanced note to separate decisions, action items, and open questions, so that follow-up work is obvious.
18. As a user, I want to edit the enhanced note directly, so that I can correct tone, emphasis, and details before sharing.
19. As a user, I want to regenerate notes from the same meeting, so that I can try a different structure without recapturing the call.
20. As a user, I want built-in templates for common meeting types, so that notes are structured appropriately without prompt engineering.
21. As a user, I want to create custom templates, so that Oatmeal matches my team's preferred note format.
22. As a user, I want to search all of my notes and transcripts, so that Oatmeal becomes a memory system instead of a pile of isolated summaries.
23. As a user, I want search results to show meaningful snippets, so that I can quickly identify the right meeting.
24. As a user, I want to chat with a single meeting note, so that I can ask follow-up questions after the fact.
25. As a user, I want to chat across several notes, so that I can detect patterns across interviews, customer calls, or project syncs.
26. As a user, I want chat to draft follow-up emails and recap messages, so that post-meeting admin work is faster.
27. As a user, I want to inspect the transcript behind a generated note, so that I can verify claims and build trust in the AI output.
28. As a user, I want to organize notes into folders, so that I can separate customer research, internal meetings, hiring, and personal conversations.
29. As a user, I want to share a polished note by link, so that teammates can read the outcome without joining Oatmeal first.
30. As a user, I want link-sharing settings to be explicit, so that I do not accidentally expose sensitive meeting content.
31. As a manager or founder, I want to review the outcomes of a meeting quickly, so that I can stay informed without reading a full transcript.
32. As a researcher, I want to compare themes across multiple conversations, so that I can synthesize patterns efficiently.
33. As a product manager, I want action items and decisions surfaced clearly, so that I can convert discussion into execution.
34. As a recruiter or interviewer, I want interview notes to follow a repeatable structure, so that candidate evaluations are consistent.
35. As a consultant or agency user, I want to keep client meeting notes organized by folder, so that context stays clean between accounts.
36. As a user, I want my note data to survive crashes or temporary connectivity failures, so that the app is dependable in real work.
37. As a user, I want Oatmeal to preserve my transcript and raw notes even if AI generation fails, so that a transient model issue does not destroy the meeting record.
38. As a user, I want to manage my calendars, defaults, and permissions from settings, so that I do not need to reinstall the app to fix configuration issues.
39. As a team user, I want to share notes with coworkers on the same domain, so that collaboration is possible without broad public links.
40. As a solo user, I want Oatmeal to be valuable without inviting anyone else, so that adoption does not depend on team rollout.

## Implementation Decisions

- Oatmeal will be built as a native macOS application using Swift and Apple UI frameworks appropriate for a modern Mac app. SwiftUI should be preferred for new surfaces, with AppKit interop where needed for mature macOS behaviors.
- The product will use a hybrid architecture: local client responsibilities for permissions, capture state, in-progress persistence, and note editing; backend responsibilities for account identity, sync, indexing, sharing, and AI orchestration.
- Audio capture will occur on-device at the macOS layer using Apple-approved capture APIs for microphone and system audio. The app will not use meeting-bot entry as a fallback in v1.
- The data model will treat a meeting note as the central object. A note contains metadata, raw notes, transcript segments, enhanced note content, sharing state, folder membership, and generation history.
- The note domain should be designed as a deep module with a stable interface that can support both calendar-backed and ad hoc notes without branching complexity leaking into UI code.
- Capture coordination should live in a dedicated Meeting Capture module responsible for permission state, active session lifecycle, timer state, transcript ingestion, and crash recovery markers.
- A Calendar Sync module should normalize Google and Microsoft event data into one internal event model used by the home screen and note creation flows.
- A Note Generation module should accept transcript text, raw note text, template instructions, and meeting metadata, then return a structured enhanced note payload. This module should be provider-agnostic behind a stable interface.
- A Template Engine module should own built-in templates, custom template CRUD, validation, and the mapping between a selected template and generation requests.
- A Search and Retrieval module should index note text, transcript text, titles, folder names, and metadata. It should provide ranked retrieval for both direct search and chat grounding.
- A Chat Orchestration module should be narrow in scope for v1: single-note Q&A and user-selected multi-note Q&A only. Global workspace chat, people/company graph chat, and autonomous workflows are deferred.
- A Sharing module should own link-token creation, privacy mode enforcement, shared note rendering payloads, and revocation behavior.
- A Sync module should use optimistic local persistence first, then reconcile to backend. The user should not lose work because the backend is briefly unavailable.
- The local persistence layer should keep in-progress notes, transcript chunks, and UI state durable enough to survive app restarts. Enhanced note generation may be remote, but draft state must not depend on immediate backend reachability.
- Authentication should be account-based rather than purely local so that sharing and multi-device sync can exist later, but v1 should still feel robust when temporarily offline.
- v1 will support folders as the only first-class organization primitive. Spaces, people/company objects, recurring rule-based filing, and automation recipes are deferred.
- Each note will belong to at most one folder in v1. Multi-folder membership is deferred to keep the local and synced data model simpler for the first release.
- v1 sharing will be read-only link sharing. Live collaborative editing is deferred to reduce concurrency and permissions complexity.
- Transcript exposure in shared views will be restricted or disabled by default because transcripts are more sensitive and harder to review than enhanced notes.
- The web surface for shared notes should remain intentionally narrow: readable formatted notes, title/metadata, and any allowed sharing context. Editing and capture stay native to macOS.
- AI provider usage must be abstracted behind internal service contracts so providers can be swapped without rewriting the rest of the app.
- Oatmeal must configure provider settings and contractual controls so customer data is not used to train third-party models.
- The app should include explicit consent and privacy UX, but legal/compliance automation such as enterprise-wide policy enforcement is deferred.
- Crash and retry flows are first-order implementation concerns, not polish. The architecture should treat generation failure, network failure, and permission revocation as common cases.

## Module Sketch

- `Account and Identity`
  Handles sign-in, session state, and account lifecycle.
- `Calendar Sync`
  Connects calendars, normalizes events, and powers upcoming meeting lists.
- `Meeting Capture`
  Owns permissions, audio capture, session state, and transcript ingestion.
- `Note Domain`
  Owns note lifecycle, metadata, raw notes, enhanced notes, and generation attempts.
- `Template Engine`
  Manages built-in and custom note templates.
- `AI Generation`
  Produces enhanced notes from transcript plus user context.
- `Search and Retrieval`
  Indexes notes and powers both search and chat context loading.
- `Chat`
  Handles grounded Q&A and drafting over selected notes.
- `Folders and Navigation`
  Organizes notes for retrieval and lightweight collaboration.
- `Sharing`
  Produces secure, revocable note links and browser-readable shared payloads.
- `Sync and Persistence`
  Preserves local durability and remote reconciliation.
- `Settings and Privacy Controls`
  Exposes preferences, permission status, and deletion flows.

## Testing Decisions

- Good tests must verify external behavior and user-visible guarantees rather than implementation details such as exact prompt wording, internal state layout, or view hierarchy trivia.
- The Meeting Capture module must be tested for state transitions including permission denied, start capture, pause/stop, failure, resume eligibility, and post-crash recovery.
- The Note Domain module must be tested for draft persistence, note creation from both calendar and ad hoc sources, regeneration behavior, and transcript-preserving failure handling.
- The Template Engine must be tested for template validation, template selection defaults, and deterministic request-shaping into the AI Generation interface.
- The AI Generation interface should be tested with contract-style tests that verify structured outputs and graceful handling of malformed provider responses.
- The Search and Retrieval module must be tested for note indexing, transcript indexing, folder filtering, and grounded retrieval for chat contexts.
- The Sharing module must be tested for privacy mode enforcement, link creation, link revocation, and exclusion of transcript content when sharing settings disallow it.
- The Sync and Persistence layer must be tested for offline-first behavior, eventual reconciliation, duplicate prevention, and durability of in-progress notes across app restarts.
- UI integration tests should cover the primary end-to-end flow: onboarding, permission gating, meeting note start, raw note editing, capture completion, enhanced note generation, and sharing.
- Performance tests should cover startup time, time to open an upcoming meeting note, transcript ingestion latency, search latency, and note-generation turnaround for realistic meeting sizes.
- Because the repo is currently greenfield, there is no codebase prior art to mirror. The testing strategy should establish a baseline suite around state-machine tests, service contract tests, sync durability tests, and a small number of high-value end-to-end UI flows.

## Release Plan

### Milestone 1: Core Capture and Notes

- Sign-in
- Calendar connection
- Upcoming meetings
- Quick Notes
- Raw notes editor
- Audio capture
- Transcript ingestion
- Enhanced note generation

### Milestone 2: Post-Meeting Utility

- Templates
- Search
- Single-note chat
- Folders
- Share by link

### Milestone 3: Reliability and Polish

- Crash recovery improvements
- Better permission repair flows
- Multi-note chat
- Search quality tuning
- Sharing/privacy polish
- Native UX refinement

## Risks

- System-audio capture on macOS is technically sensitive and can become the pacing item for the whole release.
- If transcription quality is poor, the whole product will feel unreliable regardless of UI quality.
- If enhanced notes are too generic, users will treat Oatmeal as a toy transcript tool instead of a workflow product.
- If local durability is weak, trust will collapse quickly because meetings are high-stakes, non-repeatable events.
- Shared note privacy mistakes would be severe and disproportionately damaging.

## Open Questions

- Should transcript streaming appear live during the meeting, or should v1 optimize for post-meeting transcript availability if live streaming adds reliability risk?
- Should chat launch in v1 with only single-note support, leaving multi-note chat to a later milestone if retrieval quality is not ready?
- Should the shared web note experience permit follow-up AI chat for viewers, or remain a static read-only surface in v1?

## Testing Decisions Confirmation

The highest-value modules to test first are Meeting Capture, Note Domain, Sync and Persistence, Sharing, and Search and Retrieval. Those modules define whether Oatmeal is dependable enough to earn trust, and they each expose clear external contracts that can be tested in isolation.

## Out of Scope

- Windows and iPhone clients
- Browser-based capture
- Meeting bots
- CRM and workspace graph features
- Enterprise SSO and admin controls
- Public API
- Rich integrations and automation
- Live multi-user collaborative editing
- Historical audio import
- Compliance targets such as HIPAA or FERPA
