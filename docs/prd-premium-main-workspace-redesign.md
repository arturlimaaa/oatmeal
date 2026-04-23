## Problem Statement

Oatmeal now has a strong local capture engine, automatic meeting detection, a lightweight recorder surface, and a real single-meeting AI workspace. The app is functionally much stronger than it looks. The main window still presents too much of that capability as a technical dashboard instead of as a premium meeting-notes product.

From the user’s perspective, the current main app still feels too much like an implementation scaffold:

- the note detail surface is overloaded with many equal-weight cards
- too much system state is visible in the primary workflow
- the main window does not yet feel calm, opinionated, or premium
- the app does not make a single note feel like the obvious center of gravity
- the AI workspace is present, but it still feels bolted onto the note instead of integrated into the note canvas
- transcript, summary, tasks, and raw notes are all available, but they are not shaped into one coherent workspace

This leaves Oatmeal visibly behind Granola on main-app quality, even though Oatmeal’s underlying engine is already credible. To feel like a strong competitor, Oatmeal needs a full main-window redesign that prioritizes clarity, hierarchy, and restraint.

## Solution

Implement a premium main-workspace redesign for macOS that makes Oatmeal feel much closer to Granola in the main app while staying consistent with Oatmeal’s local-first architecture and Jamie-inspired recorder surfaces.

From the user’s perspective:

- the main app becomes a calm, focused meeting workspace instead of a stack of utility cards
- the left side remains lightweight navigation
- the middle column becomes a strong notes/meetings list with better scanability
- the right side becomes one dominant note canvas
- each meeting note feels like a cohesive workspace rather than a collection of debug sections
- the user can move naturally between `Notes`, `Transcript`, `AI`, and `Tasks` without scrolling through a long inspector
- system/runtime/process information becomes secondary, tucked behind disclosure or a dedicated technical panel instead of occupying prime space
- the AI workspace becomes note-native, persistent, and high-trust rather than just one more card

This milestone is a structural and visual redesign of the main app. It is not a pure styling pass. The goal is to turn Oatmeal’s current capabilities into a premium user experience that feels closer to Granola’s product quality.

## User Stories

1. As a meeting-heavy macOS user, I want the main app to feel calm and premium, so that Oatmeal feels like a product I want open all day.
2. As a meeting-heavy macOS user, I want the note itself to be the center of the interface, so that the app feels built around my meeting rather than around internal machinery.
3. As a meeting-heavy macOS user, I want the main workspace to privilege what I need most after a meeting, so that I can read, edit, and act without hunting through the UI.
4. As a meeting-heavy macOS user, I want the navigation and note list to stay lightweight, so that the note canvas has visual priority.
5. As a meeting-heavy macOS user, I want the current app’s long stack of cards to be replaced with a more intentional workspace, so that the interface feels designed rather than accumulated.
6. As a meeting-heavy macOS user, I want one dominant note canvas on the right, so that each meeting feels like a proper document.
7. As a meeting-heavy macOS user, I want the list of meetings and notes to be easy to scan, so that finding the right note is fast.
8. As a meeting-heavy macOS user, I want upcoming meetings and past notes to feel visually coherent, so that Oatmeal reads like one product instead of multiple modes.
9. As a meeting-heavy macOS user, I want the main note surface to emphasize summary, decisions, tasks, and transcript access in a clear hierarchy, so that I can understand the meeting quickly.
10. As a meeting-heavy macOS user, I want to move between note views like `Notes`, `Transcript`, `AI`, and `Tasks`, so that I do not have to scroll through everything at once.
11. As a meeting-heavy macOS user, I want the default note view to prioritize the polished meeting note, so that Oatmeal feels useful immediately after processing completes.
12. As a meeting-heavy macOS user, I want the transcript to feel like a purposeful secondary view, so that it is available when needed without dominating the main workspace.
13. As a meeting-heavy macOS user, I want raw notes to feel like working material, so that they support the final note without visually competing with it.
14. As a meeting-heavy macOS user, I want tasks and action items to feel like a real part of the note, so that follow-up work is easier to scan and trust.
15. As a meeting-heavy macOS user, I want the AI workspace to feel integrated into the note instead of bolted on, so that asking questions or generating drafts feels natural.
16. As a meeting-heavy macOS user, I want the AI workspace to stay scoped clearly to the current meeting, so that Oatmeal remains trustworthy.
17. As a meeting-heavy macOS user, I want AI actions and freeform prompts to live in a clear, durable note-native thread, so that the experience feels like part of the document.
18. As a meeting-heavy macOS user, I want source citations to feel readable and useful inside the workspace, so that grounded answers remain trustworthy.
19. As a meeting-heavy macOS user, I want the app to stop showing runtime internals in the primary note canvas, so that the interface feels premium instead of diagnostic.
20. As a meeting-heavy macOS user, I want technical state such as runtime choices, capture permissions, and pipeline details to be available only when I need them, so that the primary UI stays clean.
21. As a meeting-heavy macOS user, I want processing progress to be shown in simple product language, so that I understand what Oatmeal is doing without reading backend terminology.
22. As a meeting-heavy macOS user, I want empty and loading states to feel designed and intentional, so that Oatmeal still feels polished before a note is complete.
23. As a meeting-heavy macOS user, I want the app to feel visually lighter even when a note contains a lot of information, so that dense meetings do not create a stressful UI.
24. As a meeting-heavy macOS user, I want the app to use whitespace, hierarchy, and restraint instead of lots of borders and badges, so that the product feels sophisticated.
25. As a meeting-heavy macOS user, I want Oatmeal to feel closer to Granola in the main window, so that it is more competitive as a daily workspace.
26. As a meeting-heavy macOS user, I want the main window and the floating recorder to feel like parts of the same product, so that Oatmeal has a coherent identity.
27. As a meeting-heavy macOS user, I want a selected meeting note to open into a focused workspace immediately, so that there is less transitional friction.
28. As a meeting-heavy macOS user, I want the AI workspace to be usable without visually taking over the entire note, so that it supports rather than replaces the core note view.
29. As a meeting-heavy macOS user, I want a note to feel good both during and after a meeting, so that the workspace supports live use and post-meeting use.
30. As a meeting-heavy macOS user, I want the main workspace to feel strong on both laptop and desktop screens, so that the product remains premium across common Mac setups.
31. As a meeting-heavy macOS user, I want the middle-column note rows to show the right amount of signal, so that I can scan title, state, and recency quickly.
32. As a meeting-heavy macOS user, I want meeting context such as participants and meeting type to be present but not noisy, so that the note remains primary.
33. As a meeting-heavy macOS user, I want the app to highlight what is most important about a meeting first, so that I can recover context in seconds.
34. As a meeting-heavy macOS user, I want quick drafts and structured AI workflows to remain easy to trigger, so that Oatmeal still feels powerful.
35. As a meeting-heavy macOS user, I want those AI actions to live in a cleaner visual system, so that they feel like polished product actions rather than utility buttons.
36. As a meeting-heavy macOS user, I want the note workspace to make transcript review and task review feel like intentional modes, so that I can shift mental context cleanly.
37. As a meeting-heavy macOS user, I want the app to make it obvious when a note is still processing versus ready, so that the product state feels legible.
38. As a meeting-heavy macOS user, I want the main window to reduce my need to open system-heavy settings or technical sections, so that normal use remains focused.
39. As a designer, I want the redesign to use fewer simultaneous panels and less card noise, so that the product feels authored.
40. As a designer, I want one strong visual direction for the main app, so that Oatmeal does not feel like a collection of disconnected experiments.
41. As a designer, I want the product to feel macOS-native without looking generic, so that it benefits from platform familiarity while still feeling distinctive.
42. As a designer, I want the note canvas to carry most of the visual weight, so that the product feels document-centric.
43. As a designer, I want motion and transitions between note modes to feel purposeful, so that the app feels modern without becoming noisy.
44. As a product engineer, I want this redesign to preserve the existing data model and core engine, so that the UI can improve dramatically without destabilizing proven behavior.
45. As a product engineer, I want the new workspace to be organized around a few durable deep modules rather than one giant view, so that iteration remains practical.
46. As a product engineer, I want note presentation state to be separated from transport/runtime state, so that UI hierarchy is not polluted by backend concerns.
47. As a product engineer, I want a dedicated workspace model for note subviews and mode selection, so that `Notes`, `Transcript`, `AI`, and `Tasks` can evolve independently.
48. As a product engineer, I want technical and operational details to move into a lower-priority disclosure model, so that the main layout stops fighting the engine model.
49. As a product engineer, I want the redesign to preserve current routing, selection, and persistence behavior, so that the UI changes do not break workflow continuity.
50. As a product engineer, I want the note detail to become simpler to reason about, so that future features like exports or multi-meeting intelligence have a cleaner home.
51. As a QA engineer, I want the redesign to preserve externally visible behavior while changing the structure, so that regression coverage remains meaningful.
52. As a QA engineer, I want the app to have stable note-mode behavior that can be tested without fragile layout assertions, so that UI polish does not make tests brittle.
53. As a support engineer, I want the user to see fewer internal states by default, so that the product is easier to explain and troubleshoot.
54. As a support engineer, I want technical state to remain accessible when needed, so that support and debugging are still possible.
55. As a future engineer, I want this milestone to establish the canonical main-app layout before cross-meeting intelligence, exports, or deeper collaboration work, so that future product breadth lands on a strong foundation.
56. As a future engineer, I want the main workspace redesign to create obvious homes for later features like export/share, richer templates, and broader AI actions, so that those features do not re-fragment the layout.

## Implementation Decisions

- This milestone is a structural redesign of the main macOS workspace, not a pure styling pass.
- The redesign should align Oatmeal’s main window more closely with Granola’s product shape:
  - calm navigation
  - stronger notes list
  - one dominant note canvas
  - integrated AI workspace
  - lower emphasis on technical internals
- The existing app architecture should remain intact at the engine level. Capture, transcription, summary generation, detection, and the single-meeting assistant already exist and should not be rewritten for this milestone.
- The main redesign should be organized around a few durable UI modules rather than one monolithic root view. At minimum, the product should introduce or clarify deep modules for:
  - workspace shell and navigation state
  - note list presentation
  - note workspace mode/state management
  - note canvas composition
  - secondary technical/details disclosure
- The note workspace should adopt a small set of intentional modes rather than presenting all detail sections at once. The canonical user-facing modes for this milestone should be:
  - `Notes`
  - `Transcript`
  - `AI`
  - `Tasks`
- The default note experience should open into the polished meeting note, not into transcript or operational details.
- The AI workspace should remain persistent per note, but visually it should become a first-class part of the note workspace rather than a same-weight card among many cards.
- The transcript should become a purpose-built note mode or panel, not just one more long section in the note detail stack.
- Raw notes should remain available, but they should be framed as working material inside the note workspace instead of occupying equal status with the polished note.
- Action items and structured AI outputs should be incorporated into the note workspace in a way that feels document-native.
- Technical/runtime/process details should move out of the primary note canvas. They may live behind:
  - a disclosure section
  - a contextual inspector
  - a lower-priority technical view
  - or settings/debug-oriented surfaces
- The redesign should explicitly reduce border density, badge clutter, and equal-weight cards.
- The redesign should use visual hierarchy, spacing, and a restrained accent strategy instead of trying to communicate importance through many separate panels.
- The note list should be redesigned to be more scanable and more product-like, with better prioritization of title, recency, readiness, and a small amount of secondary metadata.
- The upcoming meetings surface and note library should be made more visually coherent with the rest of the workspace. They should feel like alternate states of the same product shell, not like distinct mini-apps.
- The redesign should remain macOS-native. Use platform-friendly navigation, selection, and typography patterns, but avoid collapsing into generic system-default utility aesthetics.
- The floating recorder/session-controller milestone already provides the lightweight live surface. This milestone should make the main workspace feel like the premium deep-work counterpart to that recorder.
- This milestone should preserve current selection, persistence, routing, and note identity behavior unless there is a compelling user-facing reason to change them.
- The milestone should be designed so that later features like export/share, stronger template workflows, or broader AI capabilities can slot into the workspace without reintroducing card sprawl.

## Testing Decisions

- Good tests for this milestone should validate externally visible behavior and navigation contracts, not implementation details of SwiftUI layout.
- The redesign should be covered through behavior-oriented tests around:
  - selecting notes and moving between workspace modes
  - preserving note-specific AI threads
  - routing to transcript mode from citations and lightweight surfaces
  - preserving current state across relaunch where applicable
  - keeping technical/disclosure content secondary without breaking access to it
- The workspace shell/state module should be tested for deterministic mode switching, selection persistence, and availability gating.
- The note workspace model should be tested for how it derives visible sections and mode availability from note state, not for exact visual tree details.
- Existing tests around AI workspace persistence, citation routing, live transcript state, and session-controller routing should be treated as prior art and preserved.
- New tests should focus on the user-facing contracts introduced by the redesign:
  - default opening mode for ready vs processing notes
  - task visibility and transcript visibility behavior
  - AI mode state continuity per note
  - technical details still accessible but not primary
- UI tests should avoid pixel-precise assertions and instead validate mode availability, transitions, and routed behavior.
- Regression coverage should ensure the redesign does not break current capture, recovery, AI workspace, or citation workflows.

## Out of Scope

- a rewrite of capture, transcription, summary, detection, or AI engines
- cross-meeting intelligence
- multi-note chat or broader RAG
- export/share flows
- team collaboration features
- iPhone, Windows, or web redesigns
- broad settings redesign unrelated to the main workspace
- a brand overhaul disconnected from the product structure
- deep recorder-surface changes beyond keeping visual coherence with the main workspace
- speaker diarization improvements
- new integrations
