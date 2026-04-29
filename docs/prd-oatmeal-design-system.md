## Problem Statement

Oatmeal now has credible capture, detection, transcription, and AI-workspace engines, and a handful of macOS surfaces to expose them. Visually, those surfaces are still inconsistent with each other. Each screen uses its own ad hoc colors, font weights, spacings, and accent choices, because the app has never had a shared visual language. A design handoff from Claude Design now provides one: warm cream paper, toasted-oat accents, editorial serif titles with a clean sans UI and mono metadata, a brand bowl mark, a leaf mark for the menu bar, and a system of theme-able tokens.

From the user's perspective, the problem is:

- Oatmeal feels like several well-built features sitting next to each other rather than one product
- the app does not yet have a recognizable identity — no coherent type system, no consistent palette, no established mark
- the menu bar surfaces, the floating recorder, the main window, and the settings pane each look like separate prototypes instead of one application
- future visual-refresh work on any single surface will re-invent these choices locally unless a foundation exists
- premium meeting-note competitors (Granola, Jamie) lead with strong visual identity; Oatmeal currently does not

For every other design PRD in this series (menu bar experience, main window, onboarding) to land cleanly, Oatmeal needs one shared design system first — colors, type, marks, and a small set of SwiftUI primitives that every surface can depend on.

## Solution

Implement the Oatmeal design system v1 as a foundation layer every other surface can build on.

From the user's perspective:

- Oatmeal looks like one product, not a stack of prototypes
- titles feel editorial; UI feels clean; metadata feels quiet
- the app has a warm, paper-like surface with restrained toasted-oat and sage accents, never shouting
- the brand mark (bowl) shows up in hero moments (onboarding, about, splash) and the leaf mark shows up in functional moments (menu bar, lockups, inline headers)
- every button, chip, keystroke pill, eyebrow label, and recording indicator reads as part of the same system
- dark mode is first-class, not an afterthought

From an implementation perspective:

- a single `OatmealDesignSystem` module (or equivalent file group) defines color tokens, type tokens, shape tokens, spacing scale, and the two marks
- color tokens follow the design handoff names: `paper`, `paper2`, `paper3`, `card`, `ink`, `ink2`, `ink3`, `ink4`, `oat`, `oat2`, `ring`, `honey`, `sage`, `sage2`, `ember`, `recDot`, `line`, `line2`
- type tokens expose three families: `serif` (Instrument Serif — titles, display), `sans` (Inter Tight — UI, body), `mono` (JetBrains Mono — timestamps, metadata, kbd)
- the leaf mark is reproduced as a SwiftUI `Shape`/`Path` so it scales crisply at any size for in-app use; the raster PNG is reserved for the menu-bar `NSImage` template
- the bowl mark is loaded from `OatmealBowl` in the asset catalog at three scales
- a small primitives set (`OMButton`, `OMSecondaryButton`, `OMKbd`, `OMEyebrow`, `OMRecDot`, `OMWaveform`, `OMCard`, `OMHairline`) is available to every surface PRD
- light and dark variants of every color token are defined; dark variant matches the handoff's "roast" palette
- system fonts fall back cleanly on machines without the Instrument Serif / JetBrains Mono families installed

Non-goals for v1 of the design system:

- no palette switcher in-app (the handoff's Cream/Honey/Moss/Roast variants are useful for design exploration but production ships one palette plus dark mode)
- no motion/animation system beyond the recording pulse and waveform (existing)
- no illustration system beyond the provided bowl raster
- no theming API for third parties or plugin surfaces

## User Stories

1. As a meeting-heavy macOS user, I want Oatmeal to look like one product across every surface, so that the app feels finished rather than assembled.
2. As a meeting-heavy macOS user, I want titles to feel editorial and premium, so that meeting notes feel worth keeping.
3. As a meeting-heavy macOS user, I want UI text to stay quiet and uniform, so that the product does not compete with my actual meeting content for attention.
4. As a meeting-heavy macOS user, I want timestamps and metadata to look like metadata, so that I can scan them without parsing full sentences.
5. As a meeting-heavy macOS user, I want the Oatmeal leaf to appear in the menu bar and in-app headers consistently, so that I can recognize the app at a glance.
6. As a meeting-heavy macOS user, I want the bowl mark to show up in welcome and hero moments, so that the product has a warm personality beyond functional chrome.
7. As a meeting-heavy macOS user, I want dark mode to feel designed, not inverted, so that late-evening use is comfortable.
8. As a meeting-heavy macOS user, I want buttons, pills, and keystroke indicators to share one visual language, so that I never have to re-learn how a surface works.
9. As a meeting-heavy macOS user, I want the recording dot to look identical everywhere it appears, so that recording state reads instantly.
10. As a meeting-heavy macOS user, I want the waveform animation to match across the popover and the live-transcript caret, so that live state feels unified.
11. As a meeting-heavy macOS user, I want the app to respect macOS accessibility settings (Dynamic Type, Increase Contrast, Reduce Motion) where the design system is used, so that Oatmeal remains usable for everyone.
12. As a product engineer, I want one place to define colors, so that new surfaces do not hardcode hex values.
13. As a product engineer, I want one place to define type styles, so that title/body/mono use is consistent without copying modifiers.
14. As a product engineer, I want the leaf mark available as both a SwiftUI `Shape` and a raster template image, so that I can use it inline in UI or hand it to `NSStatusItem`.
15. As a product engineer, I want the bowl mark available from the asset catalog at 1x/2x/3x, so that onboarding and brand surfaces render crisply on any Mac.
16. As a product engineer, I want a small primitives set (button, secondary button, kbd, eyebrow, rec dot, waveform, card, hairline), so that subsequent visual-refresh PRDs can consume them directly rather than reinventing.
17. As a product engineer, I want dark-mode tokens to live in the same definitions as light-mode tokens, so that dark is not an afterthought.
18. As a product engineer, I want every token to be named after its semantic role (e.g. `ink3`, `paper2`, `rec-dot`) rather than its hex value, so that future palette tweaks do not require rewriting call sites.
19. As a product engineer, I want type tokens to fall back to system fonts when Instrument Serif or JetBrains Mono are unavailable, so that Oatmeal does not break on machines that lack the brand fonts.
20. As a product engineer, I want the design system to ship without blocking on font licensing, so that implementation can begin before legal sign-off if needed.
21. As a product engineer, I want primitives to be state-agnostic (no ViewModel coupling), so that they can be reused anywhere without pulling in unrelated state.
22. As a product engineer, I want the design system module to have zero dependencies on `OatmealApp` state, so that it can be unit-tested and previewed in isolation.
23. As a product engineer, I want per-primitive SwiftUI previews, so that visual regressions are caught before shipping.
24. As a product engineer, I want the leaf `Shape` to accept a size and tint, so that it can match surrounding type or color context.
25. As a product engineer, I want a single `Color.om.*` accessor style (or equivalent) so that token use reads consistently across files.
26. As a product engineer, I want all color tokens to be defined once, with light + dark variants in the same definition, so that tokens cannot drift apart.
27. As a product engineer, I want layout spacing tokens (e.g. 4/8/12/16/20/24/32/48) to prevent magic-number padding across surfaces.
28. As a product engineer, I want the design system to remain source-of-truth for the `oatmeal.css` tokens in the design handoff, so that the mapping is explicit and testable.
29. As a product engineer, I want visual-refresh PRDs to reference tokens and primitives by name rather than duplicating hex values, so that future palette changes stay cheap.
30. As a product engineer, I want the design system implementation to be the first PRD shipped in this series, so that no subsequent surface is rewritten to match a later foundation.

## Scope Boundaries

**In scope:**
- Color tokens (light + dark), type tokens, spacing scale, shape/radius tokens
- `OatLeafMark` as SwiftUI `Shape` + template `NSImage` generator
- `OatmealBowl` in asset catalog (1x/2x/3x); already staged
- Primitives: `OMButton` (primary + secondary), `OMKbd`, `OMEyebrow`, `OMRecDot`, `OMWaveform`, `OMCard`, `OMHairline`
- SwiftUI previews for every primitive
- Font loading + fallback
- Unit tests confirming each named token resolves to a non-nil `Color` in both schemes

**Out of scope:**
- In-app palette switcher (Cream/Honey/Moss/Roast)
- Motion system beyond rec-pulse + waveform
- Illustration system beyond bowl
- Re-styling any existing surface — those are separate PRDs
- Replacing existing view models or persistence

## Dependencies

- None. This is the foundation every other design PRD depends on.

## Success Criteria

- Every color, type style, and primitive used in subsequent visual-refresh PRDs exists in the design system module.
- No surface PRD in this series needs to hardcode a hex value, font size, or radius.
- Dark mode renders without contrast regressions against light mode on every primitive.
- The Oatmeal leaf renders identically (to the pixel on @2x) between the menu-bar template image and an inline `OatLeafMark` at 16pt.
