## Parent PRD

#1

## What to build

Implement the first end-to-end live-session slice from the near-live transcription PRD. Add a persisted live-session state model for active meetings, expose basic session health states in the app, and add an optional transcript panel scaffold the user can open during a meeting. This slice should wire through storage, app state, and UI, but it can use placeholder incremental transcript entries until real chunked transcription lands in the next slice.

## Acceptance criteria

- [ ] A meeting note can enter and persist a live-session state distinct from post-capture processing state.
- [ ] The app exposes basic live-session health states such as live, delayed, and recovered in a user-visible way.
- [ ] The note UI includes an optional transcript panel for active sessions, and that panel can render incremental transcript content from the live-session state.

## Blocked by

None - can start immediately

## User stories addressed

- User story 5
- User story 10
- User story 12
- User story 17
- User story 25
- User story 28
- User story 31
- User story 38
- User story 39
- User story 40
