## Parent PRD

#1

## What to build

Implement near-live background transcription for one active meeting using chunked processing. While a meeting is being recorded, Oatmeal should continuously enqueue and process transcript chunks, merge those chunks into one durable transcript, and surface that progress in the transcript panel and live-session state. This slice should build the first real live transcription path rather than waiting until capture stops.

## Acceptance criteria

- [ ] Active meeting capture produces durable transcript progress before the meeting ends.
- [ ] Chunked transcript results merge into one coherent transcript without obvious duplication or dropped text at chunk boundaries.
- [ ] The transcript panel and live-session state update during the meeting as chunk work completes.

## Blocked by

- Blocked by #2

## User stories addressed

- User story 2
- User story 4
- User story 6
- User story 11
- User story 13
- User story 18
- User story 19
- User story 20
- User story 32
- User story 42
- User story 44
