## Problem Statement

Oatmeal asks for three operating-system permissions — microphone, system audio (via screen recording), and calendar — and today it asks for them reactively, in the middle of a user's first real attempt to capture a meeting. That creates three product problems at the worst possible moment:

- the user's first impression of Oatmeal is a stack of macOS dialogs, not the app's personality
- the macOS screen-recording prompt is particularly confusing because users read it as "the app wants to record my screen" and bail out at a disproportionate rate
- there is no narrative context up front explaining *why* Oatmeal needs each permission, what stays local, and what the product actually does once they are granted

From the user's perspective, the problem is:

- I install Oatmeal and immediately get hit with permission prompts I don't fully understand
- I don't know what the product is going to do with the permissions I am granting
- I don't know whether my audio is being uploaded or kept on my Mac
- I abandon the flow when a permission prompt looks scarier than I expected
- I never see a welcome screen, a brand moment, or an explanation of the local-first story before I am asked to trust the product

For Oatmeal to land a warm, premium first-run experience that matches its local-first promise, it needs a deliberate, paced onboarding surface — one that introduces the product, explains each permission in plain language, stages itself *in front of* the macOS dialogs, and degrades gracefully when a user declines.

## Solution

Implement a first-run onboarding window that walks users through a short welcome and a three-step permissions flow before Oatmeal asks for anything at the OS level.

From the user's perspective:

- when I launch Oatmeal for the first time, I see a welcome screen with the bowl mark and a short warm description of what the product is
- I advance to a three-step permissions screen that introduces each permission with a plain-language description of what it does and what stays local
- each permission row is labeled with a clear status: `Not set`, `Requested…`, `Granted`, or `Denied`
- when I tap a permission row, Oatmeal shows a brief pre-prompt explanation tailored to that permission (especially for system audio, which is the weakest link), then triggers the real macOS dialog
- I can skip calendar; I cannot skip microphone (recording would not work); system audio is encouraged but not required
- if I decline a permission, Oatmeal tells me what is still possible and how to re-grant later (Settings pane)
- the onboarding window feels like one calm surface, not a carousel of marketing slides
- I see the leaf mark in the top-left of the right pane and the bowl mark in the left pane — the same brand language I will see later in the app
- on completion, the window closes and Oatmeal places its leaf in the menu bar; the first-launch experience is over

From an implementation perspective:

- a new SwiftUI window scene `Onboarding` is presented on first launch when no onboarding-complete flag is set in persistence
- the scene is a fixed-size 900×640 window with the design-system's `paper2` left rail and `paper` right pane (matches the handoff's `OnboardingScreen`)
- three `PermRow` primitives live in the design system and bind to real permission state via the existing `CaptureAccessService` and `CalendarAccessService`
- a pre-prompt sheet or inline explainer is shown before the macOS system-audio dialog specifically (per the chat transcript's "Sam to mock pre-prompt" finding)
- onboarding completion is persisted so the scene never re-appears unintentionally; a developer-only reset lives in Settings for testing
- the existing `MeetingDetectionPromptWindowRootView` scene and the menu-bar leaf are both suppressed until onboarding completes, to avoid a confusing overlap

## User Stories

1. As a first-time macOS user, I want a calm welcome screen when I launch Oatmeal, so that I know what the app is before it asks me for anything.
2. As a first-time macOS user, I want the welcome to explain Oatmeal's local-first story up front, so that I can decide whether to trust it before granting anything.
3. As a first-time macOS user, I want the three permissions introduced together with one sentence each, so that I understand the shape of the whole ask before being asked for any single one.
4. As a first-time macOS user, I want a pre-prompt in front of the system-audio dialog specifically, so that I understand the macOS screen-recording dialog is not actually asking to record my screen.
5. As a first-time macOS user, I want each row to show a clear status (`Not set`, `Requested…`, `Granted`, `Denied`), so that I always know where I am in the flow.
6. As a first-time macOS user, I want to skip calendar and still use the product, so that I can try Oatmeal without committing to calendar integration.
7. As a first-time macOS user, I want to see the bowl mark and the leaf mark in onboarding, so that the brand language is consistent with what I will see later.
8. As a first-time macOS user, I want onboarding to be short (three steps, no multi-slide tour), so that I can get to capturing a meeting quickly.
9. As a first-time macOS user, I want to close onboarding and re-open it from Settings, so that I can revisit it after I decline something.
10. As a first-time macOS user, I want the `Continue` button to stay disabled or guide me when I have not granted microphone, so that I do not exit onboarding into a broken state.
11. As a first-time macOS user, I want Oatmeal to explain what is still possible if I decline system audio, so that I do not think I have broken the product.
12. As a first-time macOS user, I want Oatmeal to remember that onboarding is done, so that it does not re-appear on every launch.
13. As a first-time macOS user, I want the onboarding window to feel sized to its content (no jagged resizes, no empty space), so that it does not feel like an unfinished surface.
14. As a first-time macOS user, I want Oatmeal to avoid showing its menu-bar icon until onboarding completes, so that I do not see two entry points competing for attention.
15. As a first-time macOS user, I want the macOS permission dialogs to appear only after I click the corresponding row, so that I am not bombarded with prompts the moment the window opens.
16. As a returning user, I want a `Reset onboarding` option in Settings (developer-only or hidden), so that I can QA the flow when needed.
17. As a user recovering from a denied permission, I want onboarding to show me the exact macOS Settings pane to re-grant, so that recovery does not require hunting through System Settings.
18. As a product engineer, I want the onboarding scene to read permission state from the existing access services, so that we do not duplicate permission logic.
19. As a product engineer, I want onboarding persistence to live alongside existing `AppPersistence.swift` storage, so that first-run state is coherent with the rest of the app.
20. As a product engineer, I want the pre-prompt sheet to be a reusable explainer component, so that future permission additions can re-use the pattern without bespoke copy per site.
21. As a product engineer, I want the onboarding window to consume design-system tokens and primitives (`OMButton`, `OMEyebrow`, `OMCard`, `OatLeafMark`, `BowlMark`), so that visual consistency is free.
22. As a product engineer, I want onboarding completion and each permission grant to be instrumented (local log, no network), so that we can iterate on grant rates during internal dogfood.
23. As a product engineer, I want the scene to degrade cleanly when Oatmeal is launched in CLI/test contexts, so that automated test runs do not hang on a window.

## Scope Boundaries

**In scope:**
- Welcome + permissions window (3 steps, step 2 = permissions, per the handoff)
- Real wiring to `CaptureAccessService` and `CalendarAccessService`
- Pre-prompt explainer for system audio specifically
- Persistence of onboarding completion
- Suppression of menu-bar icon and auto-detection prompts until onboarding completes
- Settings-side reset (hidden or developer-only)

**Out of scope:**
- Multi-page product tour beyond welcome + permissions
- Account creation, sign-in, or sync (Oatmeal is local-first)
- Paywalls, upsells, or any monetization surface
- Keyboard-shortcut training or shortcut customization
- Deep dark-mode contrast tuning beyond what the design system delivers

## Dependencies

- `prd-oatmeal-design-system.md` (foundation tokens, marks, primitives)
- Existing `CaptureAccessService.swift`, `CalendarAccessService.swift` (permission state)
- Existing `AppPersistence.swift` (completion flag)

## Success Criteria

- A first launch on a fresh Mac produces exactly: welcome → permissions → menu-bar icon appears. No other dialogs or surfaces interrupt.
- Microphone grant rate in internal dogfood is ≥85% (baseline: existing reactive flow).
- System-audio grant rate in internal dogfood is ≥80% (baseline per the design chat transcript: 74%).
- Onboarding is idempotent: quitting mid-flow and relaunching resumes at the same step.
- No surface regresses (menu bar, detection prompt, capture engine) because of onboarding.
