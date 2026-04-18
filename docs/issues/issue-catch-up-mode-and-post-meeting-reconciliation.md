## Parent PRD

#1

## What to build

Implement catch-up behavior and final reconciliation for the near-live transcription path. If live transcription falls behind, Oatmeal must continue recording, preserve the artifact, and automatically reconcile any unfinished transcript work after or near the end of the meeting. The final enhanced-note path should reuse the reconciled near-live transcript instead of retranscribing the whole meeting from scratch.

## Acceptance criteria

- [ ] If live transcription falls behind, the meeting recording continues and the session enters a user-visible catch-up or delayed state rather than failing capture.
- [ ] Any unfinished transcript work is reconciled after the meeting using the same durable transcript model.
- [ ] Final enhanced note generation reuses the reconciled near-live transcript and only cleans up artifacts when recovery is no longer needed.

## Blocked by

- Blocked by #3

## User stories addressed

- User story 1
- User story 7
- User story 8
- User story 15
- User story 21
- User story 26
- User story 27
- User story 33
- User story 34
- User story 41
- User story 43
