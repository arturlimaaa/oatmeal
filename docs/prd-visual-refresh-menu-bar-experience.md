## Problem Statement

Oatmeal's menu-bar-first operating model is already in place. The leaf template icon sits in the menu bar, `MenuBarExtra` hosts the live session controller, and the auto-detection PRD has introduced a meeting-detected prompt surface. What's missing is visual polish: these transient surfaces are the parts of Oatmeal that users look at most often during a meeting, and they currently look utilitarian next to the design-handoff mocks for the same surfaces.

From the user's perspective, the problem is:

- the menu-bar popover that appears while recording looks like a settings pane, not a premium recorder
- the meeting-detected prompt reads as a standard system notification rather than a warm, branded moment
- source cards (Mic / System audio) are present but do not visually communicate "live" the way the design intends
- the local-guarantee footer ("Audio stays on this Mac") does not appear in the current surfaces, even though it is central to the product's privacy story
- the recording dot, waveform, and keystroke pill do not yet share a consistent visual language with the rest of the app

This PRD is a **visual refresh addendum** — the functional scope of the menu-bar-and-floating-session-controller PRD and the auto-detection-and-start-flow PRD is unchanged. What changes is how these surfaces look, how they use the design system, and how warm and premium they feel.

## Solution

Land the menu-bar experience visuals from the design handoff on top of the existing functional scope.

From the user's perspective:

- the menu-bar leaf shows a pulsing red dot when recording, invisibly crisp otherwise (already in place)
- clicking the leaf opens a warm cream/paper popover with a blur-translucent background, an arrow nub pointing at the leaf, an editorial serif title, and a 60-bar live waveform across the top
- inside the popover, Mic and System audio appear as two equal cards with a tiny live waveform per source
- Pause and Stop sit in the control row, with `⌘⇧9` shown as a kbd pill
- a hairline-separated footer reads "Audio stays on this Mac. Transcribing locally." with a small lock glyph
- when Oatmeal detects a meeting, a **dark** translucent prompt appears top-right of the screen — warm paper ink on a near-black blur, editorial serif headline ("A meeting looks like it just started.") with the meeting context on the next line, two buttons (`Record this` / `Not a meeting`), and a countdown bar underneath showing auto-start
- the prompt is clearly branded Oatmeal (leaf top-left, "now" timestamp top-right)
- both surfaces respect the design system's type, color, and spacing tokens

From an implementation perspective:

- existing `SessionControllerScenes.swift` / `OatmealMenuBarContent` is restyled to consume design-system primitives
- the `RecorderPopover` visual layout from `recorder.jsx` is reproduced as SwiftUI in the `MenuBarExtra` content (340pt wide, blur translucent background, editorial serif title)
- the waveform component (`OMWaveform`) from the design system is the source of truth for all waveform instances
- the meeting-detected prompt surface (already a window scene) is restyled to match `DetectPrompt` in `recorder.jsx` — dark translucent, warm foreground, countdown bar, two-button row
- both surfaces render the `OatLeafMark` from the design system, not a local duplicate
- auto-start countdown binds to existing auto-detection state; the visual is purely a new presentation layer

Non-goals for this refresh:

- no new detection logic, no new session-controller capabilities
- no new keyboard shortcuts
- no change to capture engine behavior
- no new settings or preferences

## User Stories

1. As a meeting-heavy macOS user, I want the recorder popover to feel warm and premium, so that the surface I see most during meetings does not feel like an engineering debug panel.
2. As a meeting-heavy macOS user, I want the popover to show a live waveform across the top, so that I can see at a glance that Oatmeal is still hearing me.
3. As a meeting-heavy macOS user, I want Mic and System audio shown as two equal cards, so that I can confirm both sources are live without reading text.
4. As a meeting-heavy macOS user, I want the recording timer shown in mono type, so that duration reads as metadata rather than as prose.
5. As a meeting-heavy macOS user, I want Pause and Stop to look clearly different (Stop is the destructive action), so that I never hit the wrong one under time pressure.
6. As a meeting-heavy macOS user, I want the keyboard shortcut for Stop shown as a kbd pill, so that I learn the shortcut without reading a help screen.
7. As a meeting-heavy macOS user, I want the popover to show the local-guarantee footer, so that the privacy story reaches me at the moment I need to trust it.
8. As a meeting-heavy macOS user, I want the popover's arrow nub to point at the menu-bar leaf, so that the surface is visually anchored to its trigger.
9. As a meeting-heavy macOS user, I want the meeting-detected prompt to appear top-right of the screen, so that it never overlaps my meeting UI.
10. As a meeting-heavy macOS user, I want the detected prompt to be dark and unobtrusive, so that it blends with the conference-app chrome I'm already looking at.
11. As a meeting-heavy macOS user, I want the detected prompt to state the meeting context in plain language ("Weekly Product Sync · Google Meet · 6 people"), so that I can decide whether to record without reading Oatmeal's internal taxonomy.
12. As a meeting-heavy macOS user, I want `Record this` to be the primary action (light button on dark), so that the path of least resistance is the right one.
13. As a meeting-heavy macOS user, I want `Not a meeting` to be the secondary action (outlined), so that dismissal is easy but not accidental.
14. As a meeting-heavy macOS user, I want an auto-start countdown bar under the prompt, so that I know how long I have to decide without reading a number.
15. As a meeting-heavy macOS user, I want the leaf mark in the prompt header, so that I know the prompt is from Oatmeal and not from the meeting app.
16. As a meeting-heavy macOS user, I want the recording dot to look identical in the menu bar, the popover, and the main window, so that recording state reads instantly everywhere.
17. As a meeting-heavy macOS user, I want the pulse animation to respect "Reduce Motion" accessibility settings, so that animation does not distract users who have opted out.
18. As a product engineer, I want both surfaces to consume design-system tokens (no local hex values), so that a palette change propagates for free.
19. As a product engineer, I want `OMWaveform` to be the single source of truth for waveform visuals, so that popover and transcript caret stay in sync.
20. As a product engineer, I want the existing session state (recording duration, sources, meeting title) to drive the refreshed popover without a new state model, so that this refresh does not fork architecture.
21. As a product engineer, I want the detected-prompt scene to remain its own window (per the existing auto-detection PRD), so that visual refresh does not affect window lifecycle.
22. As a product engineer, I want the countdown bar to derive its progress from existing auto-start timers, so that we do not introduce a second clock.
23. As a product engineer, I want SwiftUI previews for both surfaces in `recording` and `idle` states, so that visual regressions are caught before shipping.

## Scope Boundaries

**In scope:**
- Restyle `MenuBarExtra` popover content to match `RecorderPopover`
- Restyle meeting-detected prompt window to match `DetectPrompt`
- Apply design-system tokens, type, marks, primitives throughout both surfaces
- Add local-guarantee footer to popover
- Add countdown bar to detected prompt
- SwiftUI previews for refreshed surfaces

**Out of scope:**
- Changes to session-controller state, auto-detection heuristics, or capture engine
- New settings, preferences, or keyboard shortcuts
- Floating meeting-HUD window (lives in its own existing PRD)
- Library or main-window surfaces (covered by `prd-visual-refresh-main-window.md`)

## Dependencies

- `prd-oatmeal-design-system.md` (tokens, marks, primitives)
- Existing `prd-menu-bar-and-floating-session-controller.md` (functional scope)
- Existing `prd-auto-detection-and-start-flow.md` (functional scope + detected-prompt scene)

## Success Criteria

- The refreshed `MenuBarExtra` popover matches `RecorderPopover` in `components/recorder.jsx` within reasonable pixel tolerance.
- The refreshed meeting-detected prompt matches `DetectPrompt` in `components/recorder.jsx`.
- No hardcoded hex values or font strings appear in either surface; everything resolves through the design system.
- All existing auto-detection and session-controller tests still pass; no functional state-model churn.
