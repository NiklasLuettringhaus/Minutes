## What changed

<!-- One or two sentences. What does this do that the previous behaviour did not? -->

## Why

<!-- The problem, not the patch. If a user reported it, their words are the best
     statement of the problem — quote them. -->

## Measured vs assumed

<!-- Any number here is either measured or labelled an estimate. Delete the row
     that does not apply; do not delete the table. -->

| Claim | Figure | How it was obtained |
| --- | --- | --- |
|  |  |  |

## Checks

- [ ] `swift test` green
- [ ] `./Scripts/check-no-user-data.sh` green (no meetings, voices or settings)
- [ ] A human looked at any pane whose layout changed (`./Scripts/uishot.sh --open`)
- [ ] Planning artifacts updated if a decision changed; nothing renumbered
- [ ] No assertion made about behaviour that was not actually observed

## Still not verified

<!-- The honest list. What does this change that no test and no look has
     confirmed? "Nothing" is a valid answer but a rare one. -->
