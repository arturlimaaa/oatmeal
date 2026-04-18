## Parent PRD

#1

## What to build

Add observability and acceptance-style coverage for the near-live engine. This slice should instrument backlog depth, chunk latency, recovery events, and session health transitions, and add targeted verification for long meetings, transcript merging, and relaunch recovery so the milestone can be tuned and trusted.

## Acceptance criteria

- [ ] The app records useful health signals for live transcription backlog, latency, and recovery behavior.
- [ ] Acceptance-style coverage exists for relaunch recovery, chunk merge correctness, and long-meeting live processing behavior.
- [ ] Session health states exposed to users map cleanly onto observable system events that can be debugged and tuned.

## Blocked by

- Blocked by #4
- Blocked by #5
- Blocked by #6

## User stories addressed

- User story 12
- User story 14
- User story 16
- User story 30
- User story 36
- User story 37
- User story 39
