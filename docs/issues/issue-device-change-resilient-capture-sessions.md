## Parent PRD

#1

## What to build

Harden active capture sessions against microphone and output-device changes. During a live meeting, Oatmeal should preserve the session whenever possible if the microphone changes, headphones disconnect, or the output device changes. If full automatic recovery is not possible, the app should enter a clear degraded state and surface actionable guidance rather than silently failing.

## Acceptance criteria

- [ ] Active meeting capture detects relevant input and output device changes while a live session is running.
- [ ] The session automatically recovers where feasible without losing the meeting recording.
- [ ] If automatic recovery is not feasible, the app surfaces a degraded but understandable state with actionable guidance.

## Blocked by

- Blocked by #2

## User stories addressed

- User story 3
- User story 22
- User story 23
- User story 24
- User story 31
- User story 35
- User story 40
