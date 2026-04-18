## Parent PRD

#1

## What to build

Implement relaunch recovery for in-flight live sessions. If Oatmeal is quit or crashes during a meeting, the app should restore the saved live-session state on relaunch, resume unfinished transcript work from durable artifacts and checkpoints, and clear recovery markers once the session is reconciled.

## Acceptance criteria

- [ ] The app can restore unfinished live-session state after relaunch.
- [ ] Saved artifacts and chunk checkpoints are sufficient to resume unfinished transcript work without restarting from zero.
- [ ] Recovery state is visible while work resumes and is cleared once reconciliation completes.

## Blocked by

- Blocked by #3

## User stories addressed

- User story 9
- User story 10
- User story 11
- User story 25
- User story 27
- User story 33
- User story 37
- User story 45
