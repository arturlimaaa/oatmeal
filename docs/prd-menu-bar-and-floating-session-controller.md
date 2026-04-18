## Problem Statement

Oatmeal now has a credible near-live capture and recovery engine, but the product still depends on the main window as its primary control surface. For a meeting app, that is too heavyweight. A user should not need to keep a full three-column app visible just to start capture, confirm that Oatmeal is healthy, glance at session state, or stop recording safely.

Right now, Oatmeal feels architecturally stronger than it feels operationally convenient. The missing piece is a lightweight, always-available macOS-native control surface that makes Oatmeal feel present during the workday without forcing the full app into the foreground.

From the user’s perspective, the problem is:

- there is no persistent menu-bar presence that communicates Oatmeal’s state at a glance
- there is no compact controller for an active meeting that can stay visible while the user works in other apps
- starting or stopping capture still feels tied to the main window instead of to the meeting itself
- degraded, delayed, recovered, and interrupted session states are implemented, but they are not surfaced in the lightweight UI that users actually want during meetings
- the current transcript panel exists only inside the main app window, which is too heavy for quick mid-meeting checks

For Oatmeal to feel like a strong macOS-native alternative to Jamie or Granola, the live engine must now be wrapped in a small, dependable control layer: menu bar first, floating session controller second.

## Solution

Implement a macOS-native recorder/session-controller milestone that adds:

- a persistent menu-bar surface for Oatmeal
- a compact floating session controller for active meetings
- one shared session model that powers the main app, the menu-bar UI, and the floating controller
- lightweight access to live status, transcript entry points, and safe session controls without requiring the full main window

From the user’s perspective:

- Oatmeal is always available in the menu bar
- the menu bar shows whether Oatmeal is idle, recording, delayed, recovered, interrupted, or finishing background work
- starting a quick note or resuming the current active meeting no longer requires opening the main app first
- when capture is active, a compact floating controller appears and stays accessible above normal app workflow
- the controller shows the current note title, elapsed time, session health, source health, and the key actions the user actually needs
- the user can open the full app or the live transcript panel only when they want more detail
- stopping capture and quitting Oatmeal while recording are treated as deliberate flows, not accidental destructive actions

This milestone should make Oatmeal feel like a day-to-day desktop utility rather than only a full-window note application.

## User Stories

1. As a meeting-heavy macOS user, I want Oatmeal to live in the menu bar, so that I can reach it quickly without opening the full app.
2. As a meeting-heavy macOS user, I want the menu-bar icon to reflect whether Oatmeal is idle or recording, so that I can confirm state at a glance.
3. As a meeting-heavy macOS user, I want the menu-bar menu to show my current session status, so that I do not have to open the full app to understand what is happening.
4. As a meeting-heavy macOS user, I want to start a Quick Note from the menu bar, so that I can begin capture in seconds.
5. As a meeting-heavy macOS user, I want to open the full Oatmeal window from the menu bar, so that the lightweight surface never blocks deeper workflows.
6. As a meeting-heavy macOS user, I want a floating recorder/controller to appear when capture starts, so that Oatmeal feels attached to the live session rather than hidden.
7. As a meeting-heavy macOS user, I want that floating controller to stay available while I work in other apps, so that I can control the meeting without context switching back to the main window.
8. As a meeting-heavy macOS user, I want the floating controller to show the current note title, so that I know which meeting Oatmeal is attached to.
9. As a meeting-heavy macOS user, I want the floating controller to show elapsed capture time, so that I can orient myself during a meeting.
10. As a meeting-heavy macOS user, I want the floating controller to show whether Oatmeal is healthy, delayed, recovered, or interrupted, so that the app feels trustworthy.
11. As a meeting-heavy macOS user, I want the floating controller to show microphone and system-audio health in a compact way, so that source-specific failures are visible without overwhelming me.
12. As a meeting-heavy macOS user, I want to stop capture from the floating controller, so that I do not need to return to the main app to end a meeting.
13. As a meeting-heavy macOS user, I want to reopen the live transcript view from the floating controller, so that I can inspect progress mid-meeting only when I need it.
14. As a meeting-heavy macOS user, I want to hide or collapse the floating controller, so that it does not permanently take over my screen.
15. As a meeting-heavy macOS user, I want the controller to reopen when a session is already active, so that I can recover the lightweight UI if I close it accidentally.
16. As a meeting-heavy macOS user, I want the menu bar and floating controller to reflect the same active session, so that the product feels coherent instead of duplicated.
17. As a meeting-heavy macOS user, I want Oatmeal to avoid showing multiple competing recorder windows, so that session control stays simple.
18. As a meeting-heavy macOS user, I want the main app, menu bar, and floating controller to stay in sync, so that state changes in one place appear everywhere else.
19. As a meeting-heavy macOS user, I want the floating controller to keep working when the session is delayed or recovering, so that the lightweight UI remains useful during problems.
20. As a meeting-heavy macOS user, I want Oatmeal to show when it is finishing background processing after capture stops, so that I know the meeting is not fully done yet.
21. As a meeting-heavy macOS user, I want quitting the app during active capture to require an explicit decision, so that I do not accidentally lose a live session.
22. As a meeting-heavy macOS user, I want a quit warning to explain what will happen to the local recording and recovery flow, so that I can make an informed decision.
23. As a meeting-heavy macOS user, I want Oatmeal to reopen gracefully after relaunch with the lightweight session state restored as much as possible, so that the recorder feels resilient.
24. As a meeting-heavy macOS user, I want the menu-bar surface to help me get back to the active meeting after relaunch, so that recovery feels magical rather than confusing.
25. As a meeting-heavy macOS user, I want the lightweight surfaces to be compact and intentional, so that Oatmeal does not feel like a generic utility panel.
26. As a meeting-heavy macOS user, I want the controller to avoid showing the full transcript by default, so that it remains a control surface rather than a second main window.
27. As a meeting-heavy macOS user, I want the controller to remain useful on both small and large displays, so that it feels native across Mac laptops and desktops.
28. As a product engineer, I want one shared session-controller adapter that derives lightweight UI state from the app model, so that the menu bar and floating controller do not fork business logic.
29. As a product engineer, I want menu-bar state to be driven by the same persisted session model as the main app, so that relaunch behavior remains consistent.
30. As a product engineer, I want the floating controller to map cleanly onto current capture states and live-session states, so that reliability work from the previous milestone is reused rather than reinterpreted.
31. As a product engineer, I want one scene/window coordination layer for the main window, settings, transcript entry points, and floating controller, so that macOS windowing logic does not sprawl through unrelated views.
32. As a product engineer, I want explicit rules for when the floating controller appears, hides, or reappears, so that the UI feels deterministic.
33. As a product engineer, I want session-control actions in the menu bar and floating controller to route through the same command layer as the main app, so that capture behavior remains testable and safe.
34. As a product engineer, I want quit-confirmation behavior to be modeled explicitly, so that destructive user flows are auditable and testable.
35. As a product engineer, I want scene-specific UI tests and adapter tests for the lightweight controller, so that future recorder polish does not regress the macOS utility behavior.
36. As a support engineer, I want the menu bar and floating controller to expose session health with product language that maps to real internal states, so that user-reported issues are easier to diagnose.
37. As a support engineer, I want the lightweight surfaces to distinguish recording, delayed transcription, recovered session, and interrupted capture, so that the user does not conflate all non-green states.
38. As a designer, I want the controller to feel like the first serious recorder surface rather than a placeholder debug palette, so that Oatmeal’s identity is reflected in the utility UI.
39. As a future engineer, I want this milestone to establish the controller shell before deeper live-recorder polish, so that later work like richer transcript peeks or device switching UI has a stable home.
40. As a future engineer, I want the menu-bar and floating-controller architecture to support later enhancements like meeting reminders, richer quick actions, or a more advanced recorder widget, so that v1 does not trap us.

## Implementation Decisions

- This PRD covers one milestone only: `menu-bar presence + floating session controller`.
- The near-live engine, capture coordination, and recovery model already exist and must remain the source of truth. This milestone builds UI orchestration and lightweight interaction on top of that engine.
- The current full main window remains the primary workspace for note detail, templates, settings, and deeper transcript inspection. The new lightweight surfaces are control-oriented, not a replacement for the main app.
- Oatmeal should gain a persistent macOS menu-bar scene. The menu-bar surface should expose:
  - overall app/session state
  - current active note title when present
  - quick actions such as open main window, start Quick Note, stop current capture, and reopen the floating controller
  - a compact status summary for active or recently completed sessions
- Oatmeal should gain one floating session controller window for the active session. This controller should:
  - appear automatically when capture begins
  - stay lightweight and compact
  - remain available above normal app workflow without becoming a full inspector
  - expose the minimum high-value controls: stop capture, open main app, open transcript surface, and collapse/close the controller
- Only one floating session controller may exist at a time. Oatmeal supports one active capture session at a time, and the lightweight UI should preserve that constraint.
- The floating controller should display:
  - note title
  - elapsed session time
  - overall session health
  - capture state
  - microphone health
  - system-audio health when applicable
  - a compact processing hint if the session has stopped but post-capture work is still active
- The floating controller should not embed the full transcript by default. At most, it may expose a transcript entry point or a small status summary in this milestone.
- The transcript panel remains a concept inside the main note experience for now. This milestone should provide a way to jump to it rather than rebuilding transcript browsing inside the floating controller.
- The menu-bar surface and floating controller should both be driven by a shared session-controller adapter layer that maps the app’s current `selected note`, `active capture session`, `live session state`, and `processing state` into lightweight UI state.
- The session-controller adapter should be a deep module. It should hide the complexity of interpreting recording state, live-session state, relaunch recovery, and post-capture processing from the menu-bar and floating UI scenes.
- Scene/window management should also be centralized. The app needs an explicit window/controller coordinator responsible for:
  - opening the main window
  - presenting or re-presenting the floating controller
  - routing to the relevant note when the user acts from the menu bar
  - preserving deterministic behavior on relaunch and while capture is active
- Quit while recording must be an explicit flow. If capture is active, quitting should surface a confirmation that explains:
  - that Oatmeal is recording locally
  - whether quitting will interrupt active capture
  - whether recovery is expected on relaunch
- The app should remain macOS-native. Prefer platform-native scenes/windowing constructs for menu bar and utility/floating windows rather than inventing a custom multi-window architecture.
- This milestone should preserve current state ownership in `AppViewModel`, but it may require extracting one or both of these deep modules:
  - a lightweight session-controller adapter
  - a scene/window coordination service
- The milestone should define explicit appearance rules for the floating controller. At minimum:
  - open automatically when capture starts
  - remain available while capture is active
  - stay reopenable from the menu bar after manual close
  - transition cleanly when capture stops and background processing continues
  - dismiss or downgrade once the session is fully complete
- This milestone should not add broad new capture capabilities. It should reuse the capture and recovery engine built in the previous milestone.
- The milestone should preserve straightforward solo-user scope. No collaboration, sharing, external control surfaces, or mobile companions are in scope.

## Testing Decisions

- Good tests for this milestone validate externally visible behavior:
  - whether the right lightweight state appears for idle, recording, delayed, recovered, interrupted, and post-processing sessions
  - whether menu-bar/floating-controller actions route to the correct app behavior
  - whether relaunch and recovery states are reflected correctly in the lightweight UI model
- The deepest logic should be tested through a session-controller adapter module rather than through brittle view assertions.
- The scene/window coordination layer should be tested for deterministic action routing and appearance rules where possible, with behavioral tests around:
  - auto-present on capture start
  - reopen behavior
  - stop-routing behavior
  - safe quit behavior during active capture
- UI tests should cover:
  - active session state reflected in the floating controller
  - delayed and recovered status visibility
  - post-capture processing visibility after stop
  - main-window jump actions from the lightweight UI
- Existing app-level async tests around live-session state, relaunch recovery, and post-capture processing should be treated as prior art. This milestone should extend those patterns rather than inventing a separate style.
- Tests should avoid binding to fragile pixel layout or exact window coordinates. The goal is to validate user-visible behavior and window/state contracts, not platform implementation quirks.

## Out of Scope

- a full Jamie-style expanded live recorder with scratchpad, mic switching UI, or dense transcript browsing
- automatic meeting reminders or auto-launch behavior before meetings
- a broad redesign of the main app window
- collaboration, sharing, exports, or integrations
- deeper chat or cross-note workflows
- true diarization or speaker identity improvements
- iPhone, Windows, or web recorder surfaces
- full App Sandbox/distribution hardening
- visual-polish-only refinements that do not materially define the product behavior of the menu bar or floating controller
