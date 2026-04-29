## Problem Statement

Oatmeal's main window already hosts a strong functional story: a meetings library, a premium single-meeting workspace that combines transcript, notes, action items, and an integrated AI mode, and summary/technical-details surfaces. The functional work is covered by `prd-premium-main-workspace-redesign.md` and `prd-single-meeting-ai-workspace.md`, both of which have recently shipped significant implementation.

The design handoff from Claude Design now provides a concrete visual language for the same three surfaces — library, workspace, and summary — that is materially warmer, more editorial, and more consistent than what ships today. The gap is visual: layouts, typography, hierarchy, and accents. The functional primitives (transcript segments, notes, action items, AI thread, citations, speaker colors) already exist.

From the user's perspective, the problem is:

- the library feels like a data table rather than a warm editorial index of my meetings
- the workspace's three columns (transcript, notes, chat) are functional but do not feel like one thoughtful surface
- notes currently read as UI content rather than as a written artifact (no editorial serif titles, no eyebrow labels, no restrained hierarchy)
- the AI chat sidebar is visible but not yet warm or grounded-feeling
- the summary view, when it exists, does not present decisions, topics, and speakers with the editorial calm the design implies
- speaker colors, action-item layouts, and citation pills are inconsistent across views

This PRD is a **visual refresh addendum** — functional scope is unchanged. What changes is visual language, layout, and how each surface consumes the design system.

## Solution

Apply the design-handoff visuals to the three main-window surfaces (library, workspace, summary) on top of the existing functional scope.

From the user's perspective (library):

- the library opens to a warm cream surface with a 220pt sidebar on the left
- the sidebar contains: a leaf + "Oatmeal" lockup, a navigation group (`All meetings`, `Today`, `Unreviewed`, `Action items`), a Folders group, and a quiet footer showing total count + local-only indicator
- a toolbar sits above the list with a search field (with `⌘K` kbd pill), a date filter button, and a primary `New meeting` button
- below the toolbar, an editorial page head announces the current filter (eyebrow label + large serif title + metadata line)
- meetings group by day; each day is preceded by a `TODAY · WED, APR 22` eyebrow
- each meeting row is a 4-column grid: time (mono), title (serif) + people (small), tag chip, duration (mono)
- a live row shows a `LIVE` pill next to the title

From the user's perspective (workspace):

- the window has a sub-toolbar with a back chevron, a recording-state chip, attendees, and three action buttons (`Summarize`, `Extract actions`, `Share`)
- the body is a 3-column grid: transcript (360pt), notes canvas (flexible, with `paper-card` background), chat sidebar (340pt)
- transcript rows are `[timestamp][speaker name + role][line]`, speaker-colored, with a live-caret row at the bottom showing the waveform + "transcribing locally…"
- the notes canvas is narrow-column, editorial serif title, mono meta line, H2 section headings with hairline dividers, body paragraphs in a quiet color, bullets with an oat-colored glyph, and an inline "Action items" card near the bottom
- the chat sidebar shows a leaf-marked header, the line "Grounded in this transcript. Never leaves your Mac.", a message list with user bubbles (ink background) and assistant bubbles (card background, border-bottom-left-radius tweaked) with citation pills below each assistant message, and a composer with a sparkle icon, placeholder text, send button, and three suggestion chips

From the user's perspective (summary):

- a large editorial header announces the meeting (eyebrow + serif title + metadata line including local-recording lock)
- a 1.3:1 two-column body below: TLDR quote with left-border oat accent, then a Decisions list with oat numeric badges, then a Topics list with time ranges and excerpts
- the right rail holds an Action items card and a Speaker share card (colored bars per speaker)

From an implementation perspective:

- the existing `OatmealRootView.swift`, workspace views, and associated state (`PremiumNoteWorkspaceState`, `PremiumTranscriptWorkspaceState`, `PremiumAIWorkspaceState`) remain the sources of truth
- this PRD adds a visual layer on top of those state models — layouts, typography, colors, primitives — without introducing new state
- any sub-view that duplicates design-system primitives is replaced with the design-system version (`OMButton`, `OMKbd`, `OMEyebrow`, `OMRecDot`, `OMWaveform`, `OMCard`, `OMHairline`)
- speaker colors are centralized in the design system (five-color palette: ring, sage-2, oat-2, ember, ink-2) and consumed uniformly across transcript, notes, summary, and citations
- citation pills are a reusable primitive that takes `{timestamp, speakerName}` and renders the handoff style
- an "Audit" task precedes implementation: the existing library, workspace, and summary surfaces are inventoried against the handoff to decide, per sub-view, whether the refresh is a prop-level change or a layout-level rewrite

Non-goals for this refresh:

- no changes to transcript chunking, citation extraction, or AI-assistant behavior
- no changes to meeting schema, persistence, or sync
- no new keyboard shortcuts or settings
- no cross-meeting chat (remains out of scope per `prd-single-meeting-ai-workspace.md`)
- no palette switcher

## User Stories

1. As a meeting-heavy macOS user, I want the library to look like an editorial index of my meetings, so that my meeting archive feels like something worth keeping.
2. As a meeting-heavy macOS user, I want meeting titles in an editorial serif, so that each meeting reads as a note rather than a row.
3. As a meeting-heavy macOS user, I want timestamps and durations shown in mono, so that I can scan temporal structure at a glance.
4. As a meeting-heavy macOS user, I want meetings grouped by day with a small eyebrow label, so that the list has rhythm without noise.
5. As a meeting-heavy macOS user, I want a live meeting shown with a `LIVE` pill, so that I can jump back to recording instantly.
6. As a meeting-heavy macOS user, I want the sidebar to show total meeting count with a lock glyph, so that I am reminded the archive is local.
7. As a meeting-heavy macOS user, I want the workspace to feel like a thoughtful surface, not a three-tool toolbox, so that I can work inside a single meeting without feeling cluttered.
8. As a meeting-heavy macOS user, I want the notes canvas to look like a written document, so that AI-generated content feels like something I might have written.
9. As a meeting-heavy macOS user, I want decisions, discussion, and actions as distinct H2 sections, so that I can scan the note without reading top-to-bottom.
10. As a meeting-heavy macOS user, I want bullets to use an oat-colored glyph, so that the document has warmth without losing calm.
11. As a meeting-heavy macOS user, I want the action-items card inline with notes, so that actions feel like part of the meeting output rather than a separate list.
12. As a meeting-heavy macOS user, I want transcript rows to be color-coded by speaker, so that I can follow a multi-speaker conversation without reading every name.
13. As a meeting-heavy macOS user, I want a live-caret row at the bottom of the transcript showing the waveform + "transcribing locally…", so that I can see progress during the meeting.
14. As a meeting-heavy macOS user, I want the AI chat sidebar labeled "Ask this meeting" with a grounded-scope reassurance line, so that I trust the assistant's boundary.
15. As a meeting-heavy macOS user, I want citation pills under AI answers, so that I can inspect the evidence without copy-pasting.
16. As a meeting-heavy macOS user, I want suggestion chips under the composer (`Summarize in 3 bullets`, `What did I commit to?`, `Draft follow-up email`), so that I can use the assistant without inventing prompts.
17. As a meeting-heavy macOS user, I want the summary TLDR to feel like a pull quote, so that I can read the single most important thing and leave.
18. As a meeting-heavy macOS user, I want decisions numbered with oat badges, so that they look like commitments rather than bullets.
19. As a meeting-heavy macOS user, I want topics shown with time ranges and excerpts, so that I can jump to context if I want to.
20. As a meeting-heavy macOS user, I want a speaker-share card, so that I have a quick read on who dominated.
21. As a meeting-heavy macOS user, I want speaker names colored consistently wherever they appear (transcript, notes, summary, citations), so that I can learn each speaker's color.
22. As a meeting-heavy macOS user, I want the recording chip in the workspace sub-toolbar to match the menu-bar recording indicator, so that live state reads the same everywhere.
23. As a product engineer, I want the refresh to reuse existing state models without changes, so that this PRD does not fork architecture with the functional PRDs.
24. As a product engineer, I want a speaker-color mapping centralized in the design system, so that speaker coloring never drifts across surfaces.
25. As a product engineer, I want a reusable `CitationPill` primitive, so that transcript, notes, and AI citations all render the same.
26. As a product engineer, I want the notes canvas to render from the existing enhanced-note data without a new content model, so that the refresh is a view-layer change only.
27. As a product engineer, I want the action-items inline card and the right-rail action-items card in the summary to share a single rendering component, so that actions look identical in both locations.
28. As a product engineer, I want to audit each surface (library / workspace / summary) against the handoff before starting implementation, so that the per-surface work is scoped accurately (prop-level vs. layout-level).
29. As a product engineer, I want the refresh to avoid `geometryReader` / manual-layout hacks where possible, so that the surfaces remain responsive to window-size changes.
30. As a product engineer, I want SwiftUI previews for each surface in populated and empty states, so that visual regressions are caught before shipping.

## Scope Boundaries

**In scope:**
- Library surface restyle (sidebar, toolbar, editorial head, day-grouped list, tag chips, live pill)
- Workspace surface restyle (sub-toolbar, 3-column grid, transcript rows + live caret, notes canvas, AI chat sidebar, citation pills, composer + suggestions)
- Summary surface restyle (editorial header, TLDR, decisions, topics, action-items card, speaker share)
- Centralized speaker-color mapping
- Reusable `CitationPill`, `ActionItemRow`, `MeetingRow` primitives

**Out of scope:**
- Any change to transcript segmentation, AI chat behavior, or citation extraction
- Any change to persistence, schema, or sync
- New keyboard shortcuts or preferences
- Menu-bar or detection-prompt surfaces (covered by `prd-visual-refresh-menu-bar-experience.md`)
- Onboarding (covered by `prd-onboarding-and-permissions.md`)

## Dependencies

- `prd-oatmeal-design-system.md` (tokens, marks, primitives)
- Existing `prd-premium-main-workspace-redesign.md` (functional workspace scope)
- Existing `prd-single-meeting-ai-workspace.md` (AI chat functional scope)
- Existing `prd-oatmeal-macos-v1.md` (library / summary functional scope)

## Success Criteria

- Each of the three surfaces (library, workspace, summary) matches its counterpart in `components/library.jsx`, `components/workspace.jsx`, `components/summary-onboarding.jsx` within reasonable pixel tolerance.
- No hardcoded hex values or font strings appear in any main-window surface; everything resolves through the design system.
- Speaker colors are consistent across transcript, notes, summary, and AI citations.
- All existing tests still pass; no state-model regressions.
- Window resize behavior is preserved or improved on each surface.
