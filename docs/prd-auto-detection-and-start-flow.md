## Problem Statement

Oatmeal can already record meetings well once the user has explicitly started capture, but it still depends too much on intentional user action. That makes the product feel less present and less magical than the strongest no-bot meeting tools.

From the user’s perspective, the problem is:

- Oatmeal does not reliably notice that a meeting has actually started
- the user still has to remember to open Oatmeal and begin capture
- ad hoc calls without a useful calendar event have no lightweight entry path
- browser-based meetings are especially easy to miss even though they are a large part of real-world usage
- the current menu-bar and floating recorder surfaces are useful once capture is active, but they do not yet help the user get into capture at the right moment
- if the user ignores a start prompt, Oatmeal has no strong passive fallback that keeps the meeting discoverable without becoming annoying

For Oatmeal to feel like a serious alternative to Jamie, it needs a Jamie-like automatic meeting-start flow: Oatmeal should notice when the user has joined a likely call, surface a minimally invasive `Start Oatmeal` prompt, optionally auto-start in high-confidence cases, and gracefully fall back to a passive menu-bar suggestion when the user does nothing.

## Solution

Implement a macOS-native automatic meeting detection and start-flow milestone that makes Oatmeal proactive instead of passive.

From the user’s perspective:

- Oatmeal watches for likely meetings across supported native apps and supported browsers
- when Oatmeal detects that the user has joined a likely meeting, it shows a lightweight Jamie-style start prompt rather than forcing the main app open
- if multiple possible meetings match, the prompt lets the user choose a candidate quickly
- if there is no matching calendar event, Oatmeal can still start as an ad hoc meeting with a temporary `Untitled Meeting` title
- if the user ignores the prompt, Oatmeal stops interrupting and keeps a passive menu-bar suggestion instead
- if the user enables optional auto-start, Oatmeal may begin capture automatically, but only for high-confidence detections
- Oatmeal can also suggest that a meeting seems to have ended, but it never auto-stops capture in this milestone

This milestone should feel Jamie-like in user experience while remaining honest about Oatmeal’s current architecture and platform constraints. Browser-call detection is mandatory, but it should be implemented with system- and app-level heuristics rather than brittle browser extensions or invasive UI scraping.

## User Stories

1. As a meeting-heavy macOS user, I want Oatmeal to notice when I join a likely meeting, so that I do not have to remember to start it manually every time.
2. As a meeting-heavy macOS user, I want Oatmeal to detect calls in Zoom, Teams, Slack, and browsers, so that my real meeting workflow is covered.
3. As a meeting-heavy macOS user, I want browser-based meetings to be first-class in detection, so that Google Meet and WhatsApp Web are not second-tier experiences.
4. As a meeting-heavy macOS user, I want Oatmeal to show a lightweight `Start Oatmeal` prompt when it detects a meeting, so that getting started feels immediate.
5. As a meeting-heavy macOS user, I want that prompt to feel minimally invasive, so that Oatmeal helps me without stealing focus.
6. As a meeting-heavy macOS user, I want Oatmeal to avoid opening the full app just to ask whether I want to start recording, so that the start flow feels native and calm.
7. As a meeting-heavy macOS user, I want Oatmeal to keep working for ad hoc calls with no calendar event, so that spontaneous meetings are still captured.
8. As a meeting-heavy macOS user, I want unmatched detected calls to start as `Untitled Meeting`, so that I can capture immediately and rename later.
9. As a meeting-heavy macOS user, I want Oatmeal to match detected meetings to nearby calendar events when possible, so that scheduled calls feel correctly attached to context.
10. As a meeting-heavy macOS user, I want Oatmeal to ask me to choose when multiple meeting candidates are plausible, so that it does not silently attach capture to the wrong meeting.
11. As a meeting-heavy macOS user, I want that meeting chooser to appear inside the lightweight prompt flow, so that I can resolve ambiguity without opening the full app.
12. As a meeting-heavy macOS user, I want Oatmeal to keep the prompt simple, so that starting a meeting never feels like navigating a setup wizard.
13. As a meeting-heavy macOS user, I want a single ignored prompt to downgrade into a passive menu-bar suggestion, so that Oatmeal does not keep interrupting me.
14. As a meeting-heavy macOS user, I want the passive menu-bar suggestion to preserve the detected meeting context, so that I can still start capture a minute later without losing the flow.
15. As a meeting-heavy macOS user, I want optional auto-start in Settings, so that I can make Oatmeal more automatic if I trust it.
16. As a meeting-heavy macOS user, I want auto-start to trigger only for high-confidence detections, so that Oatmeal does not start recording by mistake too often.
17. As a meeting-heavy macOS user, I want per-app detection controls, so that I can disable sources I do not trust or do not use.
18. As a meeting-heavy macOS user, I want to enable or disable detection separately for Zoom, Teams, Slack, and browsers, so that detection reflects my workflow.
19. As a meeting-heavy macOS user, I want launch-at-login to be recommended for this feature, so that auto-detection is actually available when I start my day.
20. As a meeting-heavy macOS user, I want Oatmeal to keep launch-at-login optional, so that I remain in control of how persistent it is.
21. As a meeting-heavy macOS user, I want Oatmeal to detect “meeting seems to have started” without requiring perfect certainty, so that it can be useful in the real world.
22. As a meeting-heavy macOS user, I want Oatmeal to optimize uncertain detections toward passive suggestions instead of aggressive alerts, so that false positives are tolerable.
23. As a meeting-heavy macOS user, I want Oatmeal to suggest when a meeting seems to have ended, so that I get help stopping capture without giving up control.
24. As a meeting-heavy macOS user, I want end-of-meeting handling to suggest rather than force a stop, so that Oatmeal never cuts off a meeting that is still going.
25. As a meeting-heavy macOS user, I want detection and start behavior to work with the existing floating recorder and menu bar, so that the product feels coherent.
26. As a meeting-heavy macOS user, I want the floating controller to appear immediately after a detected meeting is started, so that the handoff from detection to recording feels seamless.
27. As a meeting-heavy macOS user, I want the menu-bar state to reflect pending detected meetings, so that Oatmeal still feels alive even before capture begins.
28. As a meeting-heavy macOS user, I want Oatmeal to keep using the main app for deeper editing and transcript work, so that the lightweight start flow stays focused.
29. As a meeting-heavy macOS user, I want detection to work even when the main window is closed, so that Oatmeal behaves like a background utility.
30. As a meeting-heavy macOS user, I want detection to continue when Oatmeal is launched at login, so that I do not have to babysit the app before my first call.
31. As a meeting-heavy macOS user, I want the detection system to be resilient across app relaunches, so that an Oatmeal restart does not make it blind to an already ongoing call.
32. As a meeting-heavy macOS user, I want Oatmeal to avoid duplicate start prompts for the same meeting, so that the experience feels stable.
33. As a meeting-heavy macOS user, I want Oatmeal to keep detection state durable enough to suppress repeated prompts for the same ongoing call, so that ignoring one prompt is respected.
34. As a meeting-heavy macOS user, I want Oatmeal to reopen a pending detection suggestion after relaunch when appropriate, so that a restart does not fully discard useful context.
35. As a meeting-heavy macOS user, I want Oatmeal to choose the right meeting candidate based on app state, audio activity, and nearby calendar context, so that detections feel intelligent.
36. As a meeting-heavy macOS user, I want browser-call detection to work without extensions, so that setup stays simple.
37. As a meeting-heavy macOS user, I want browser-call detection to avoid OCR or brittle window scraping, so that the system is more maintainable and less invasive.
38. As a meeting-heavy macOS user, I want Oatmeal to avoid pretending it knows participant identity at detection time, so that wrong assumptions do not degrade trust.
39. As a meeting-heavy macOS user, I want Oatmeal to start capture quickly once I accept the prompt, so that the app does not miss the opening of the conversation.
40. As a meeting-heavy macOS user, I want Oatmeal to reuse the same permission and capture pipeline after automatic detection, so that auto-start sessions are as reliable as manually started ones.
41. As a meeting-heavy macOS user, I want Oatmeal to handle missing permissions gracefully during a detected start, so that I understand why capture cannot begin.
42. As a meeting-heavy macOS user, I want Oatmeal to fall back from auto-start to prompt or passive suggestion when confidence drops, so that it behaves conservatively when uncertain.
43. As a meeting-heavy macOS user, I want Oatmeal to clearly tell me which app or browser triggered detection when helpful, so that prompts feel explainable instead of random.
44. As a meeting-heavy macOS user, I want Oatmeal to distinguish a likely call from generic media playback, so that it does not constantly mistake normal computer use for meetings.
45. As a meeting-heavy macOS user, I want Oatmeal to use a confidence model rather than one hardcoded signal, so that the system can improve without rewriting the entire product flow.
46. As a meeting-heavy macOS user, I want Oatmeal to support multiple possible app sources without creating overlapping prompts, so that one likely meeting results in one coherent start flow.
47. As a meeting-heavy macOS user, I want Oatmeal to suppress new detection prompts when I am already recording, so that the product never competes with its own active session.
48. As a meeting-heavy macOS user, I want Oatmeal to suppress detection prompts while a session is still finishing post-capture work if that work belongs to the same meeting context, so that the product does not feel confused.
49. As a meeting-heavy macOS user, I want Oatmeal to preserve the option to rename an ad hoc detected meeting later, so that starting quickly does not lock in bad metadata.
50. As a meeting-heavy macOS user, I want Settings to explain what auto-detection watches and what it does not, so that I can trust the feature.
51. As a meeting-heavy macOS user, I want Oatmeal to explain that browser detection uses heuristics, so that the product sets realistic expectations.
52. As a meeting-heavy macOS user, I want Oatmeal to expose per-app detection toggles in a straightforward way, so that I can tune it without digging through hidden menus.
53. As a meeting-heavy macOS user, I want Oatmeal to preserve solo-user simplicity in this milestone, so that the feature improves daily workflow without dragging in team complexity.
54. As a meeting-heavy macOS user, I want the auto-detection layer to make Oatmeal feel closer to Jamie’s “it just appears when I join” experience, so that the product gap feels meaningfully smaller.

## Implementation Decisions

- This milestone focuses on automatic meeting detection and start flow only. It builds on the existing capture, near-live transcription, and lightweight recorder/controller work rather than replacing them.
- Oatmeal should aim for a Jamie-like experience: detect likely meeting starts, show a minimally invasive `Start Oatmeal` prompt, and transition into the existing capture/session-controller flow.
- Browser-call detection is mandatory for this milestone, alongside supported native apps such as Zoom, Teams, and Slack.
- Browser-call detection should use system- and app-level heuristics such as running/foreground app state, microphone/system-audio activity, and nearby calendar context. Browser extensions, OCR/window-title scraping, and reading participant lists from call UIs are out of scope.
- The product should support ad hoc calls with no calendar event. When detection cannot resolve to a calendar event, the meeting starts as `Untitled Meeting`, and the user may rename it later.
- Oatmeal should never auto-start by default. Auto-start is an optional setting.
- Auto-start should trigger only for high-confidence detections.
- The default interaction model should prioritize least-annoying behavior:
  - one prompt per detected meeting instance
  - if ignored, downgrade to a passive menu-bar suggestion only
  - avoid repeated alerting for the same ongoing meeting
- The start surface should be lightweight and system-friendly rather than a forced main-window flow. The prompt should feel comparable to Jamie’s recorder start prompt.
- When multiple candidate meetings are plausible, Oatmeal should present a compact picker inside the prompt flow rather than opening the full app.
- Detection should support both scheduled meetings and ad hoc meetings, but the triggering condition is based on “the user joined a likely call,” not “a calendar event exists.”
- Oatmeal should also detect likely meeting-end boundaries and offer a stop suggestion, but it must never auto-stop in this milestone.
- Launch at login should remain optional, but the product should recommend it because auto-detection is materially weaker if Oatmeal is not already running.
- Detection should optimize uncertain cases toward passive menu-bar suggestions rather than aggressive prompts.
- The milestone should introduce these deep modules:
  - a `MeetingDetectionEngine` that watches system/app signals and emits likely meeting-start and meeting-end detections
  - a `DetectionPolicy` that owns per-app enablement, confidence thresholds, auto-start rules, and prompt suppression behavior
  - a `MeetingCandidateResolver` that maps detections to nearby calendar meetings or an ad hoc `Untitled Meeting`, including multi-candidate resolution
  - a `DetectionPromptCoordinator` that owns the prompt lifecycle, passive menu-bar fallback, and transition from detection into active capture
  - a `MeetingBoundaryDetector` that interprets ongoing heuristics into “meeting likely started” and “meeting likely ended” suggestions
- The existing menu-bar and floating session-controller surfaces should be extended rather than bypassed. Detection should feed the current lightweight surfaces instead of inventing an unrelated recorder flow.
- State ownership should remain centered in the app model, but the detection logic itself should be extracted into deep, testable modules rather than embedded directly into views or ad hoc timers.
- The milestone should explicitly avoid broadening scope into Windows, iPhone, broad integrations, team workflows, consent automation, diarization changes, or automatic stop behavior.

## Testing Decisions

- Good tests for this milestone validate externally visible behavior: whether a likely meeting detection produces the right prompt or passive suggestion, whether candidate resolution picks the right meeting or asks the user to choose, whether ignored prompts are suppressed correctly, and whether accepted detections transition cleanly into the existing capture flow.
- Tests should focus on externally observable contracts rather than implementation details like exact timer cadence or low-level heuristic internals.
- The `MeetingDetectionEngine` should be tested with simulated app/audio/calendar signals, including browser and native-app scenarios, duplicate detections, uncertain detections, and ongoing active-session suppression.
- The `DetectionPolicy` should be tested for per-app enablement, high-confidence auto-start gating, ignored-prompt suppression, and passive fallback behavior.
- The `MeetingCandidateResolver` should be tested for matching nearby calendar events, multi-candidate ambiguity, and ad hoc `Untitled Meeting` fallback.
- The `DetectionPromptCoordinator` should be tested for one-prompt-then-passive behavior, candidate-picker behavior, start routing, and end-of-meeting stop suggestions.
- The `MeetingBoundaryDetector` should be tested for start and end suggestion behavior across noisy or incomplete signals.
- App-level tests should verify that accepting a detected meeting uses the existing capture/session-controller pipeline and that ignored detections are still visible in the menu bar.
- Prior art in the codebase already exists for testing session-controller adapter logic, command routing, relaunch recovery, and async app-level orchestration. This milestone should extend those behavioral testing patterns.

## Out of Scope

- Windows support
- iPhone support
- broad integrations
- team workflows
- browser extensions
- OCR or window-title scraping
- reading participant lists from meeting UIs
- automatic meeting stop
- consent notice automation
- diarization or speaker-identity improvements
- auto-joining meetings
- a broad redesign of the existing capture or transcript engine
