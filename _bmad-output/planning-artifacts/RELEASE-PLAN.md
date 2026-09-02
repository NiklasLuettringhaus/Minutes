---
title: Release plan — getting Minutes onto someone else's Mac
date: 2026-09-02
status: amended 2026-09-02 — the distribution decision was taken
scope: increments 6, 7 and 8 (Epics 11, 12, 13)
supersedes: nothing; this is the first plan aimed at a machine other than the author's
---

# Release plan

Minutes works. It has recorded thirteen real meetings, it has 153 passing tests,
and it is installed and running. What it has never done is run on a Mac that is
not the author's, and that turns out to be a different problem from the one the
project has been solving.

This plan has three increments and one decision. The decision gates the second
increment entirely, so it comes first.

## The decision: an Apple Developer ID, $99/year

**Everything about "one simple command" depends on this, and not for the reason
I expected.** I assumed signing was about the scary dialog on first launch. It is
about that, but the larger cost is permissions.

Apple's TN3127 documents how macOS tracks app identity for permissions: it
records the app's *designated requirement* when consent is granted, and re-checks
it on every access. Apple's own words on the current situation:

> Ad hoc signed code, called Sign to Run Locally by Xcode, has a DR but it's tied
> to that specific version of the code. In both cases macOS can't reliably track
> the identity of the code.

A Developer ID signature's requirement checks three things — signed by an Apple
identity, matching bundle identifier, matching Team ID. **It does not check a hash
of the binary.** So:

| | Signing | Cost | First launch | After an update |
| --- | --- | --- | --- | --- |
| Today | ad-hoc | $0 | Blocked. Requires System Settings → Privacy & Security → Open Anyway, re-authentication, then a second confirmation | **Microphone and system-audio consent revoked.** Re-grant both, re-run the audio test |
| Developer ID only | Developer ID | $99/yr | Same detour — Apple has required notarization for Developer ID software since 2019 | Consent survives |
| Developer ID + notarized | Developer ID | $99/yr | One dialog with an Open button. Works offline | Consent survives, and survives certificate renewal |

Two things make this sharper than it was a year ago:

- **macOS 15 removed the Control-click → Open shortcut.** The gentle bypass is
  gone; an unnotarized app now requires a trip into System Settings. Your
  colleague's first experience of Minutes would be a security warning and a
  four-step override.
- **Homebrew closed the other door on 1 September 2026 — yesterday.** Homebrew
  applies macOS quarantine to every cask install, from any tap, so Gatekeeper
  runs its checks. The `--no-quarantine` escape hatch is **gone**: I checked
  Homebrew 6.0.20 on this machine, and the flag is absent from
  `brew install --cask --help` and rejected as an argument. Official
  `homebrew/cask` is now removing casks that fail Gatekeeper outright.

So the honest statement is: **without a Developer ID, "one command" is not
achievable through Homebrew.** The fallback is a script that builds from source
on the colleague's machine — locally built apps are never quarantined — but that
requires Xcode on their Mac and several minutes of compiling, and it is a
different promise from the one you asked for.

**Recommendation: buy it.** $99/year, individual enrolment, no D-U-N-S number,
no company entity needed. It converts a four-step security detour into one
click, and it stops every update from costing your colleague their microphone
permission. That second thing is the one that would otherwise generate a support
request per release, forever.

## What "releasable" means here

Four gates. Each is checkable, and none is a matter of taste.

1. **It does not fail silently on a machine unlike the author's.** Today it does.
2. **Installing is one command, and the app opens.**
3. **Updating does not cost the user their permissions or their data.**
4. **Uninstalling actually removes everything, and the app can say what
   "everything" is.**

---

# Increment 6 — Works on a Mac that is not mine

**Epic 11.** This comes first, and not for tidiness: shipping the current build
to a colleague would hand them an app that fails without saying why. Every item
below was verified by reading the code, with the file and line recorded — none is
inferred from behaviour.

## 11.1 — BLOCKER. A failed start says nothing at all

`AppState.lastError` is written on four different failure paths in
`SessionCoordinator.swift` (lines 38, 48, 57, 61) and read by exactly one place
in the whole tree: `App/SelfTest.swift:43`, a command-line path. **No file under
`Sources/Minutes/UI/` reads it.**

So: your colleague clicks Start Recording, macOS asks for the microphone, they
click Don't Allow — and the icon stays grey, the menu still says "Start
Recording", and nothing anywhere says why. The remedy strings already exist and
are good (`MinutesError.swift:81` — "Open System Settings > Privacy & Security >
Microphone and enable Minutes"). They are simply unreachable from the interface.

The same silence covers a desktop Mac with no microphone attached
(`MicCapture.swift:27`). The author has a laptop, so that path has never run.

**Fix:** the window and the menu surface `lastError` with its remedy. This is
the single highest-value change in the plan — it is the difference between "it
didn't work" and "it told me what to do".

## 11.2 — HIGH. The evidence that system audio worked does not test for audio

`SystemTapCapture.swift:171`:

```swift
let gotAudio = (writer?.peak ?? 0) > 0.0001 || d > 0.25
```

The comment three lines above says `producedAudio` is *"the only evidence we can
have that system-audio capture actually worked"* — because macOS exposes no API
to query that permission (FR-42). The `|| d > 0.25` clause makes **a quarter
second of pure silence sufficient**. Frames are written whether or not anything
is playing.

That value flows into `Preferences.lastSystemCaptureOK` and then into sentences
that assert a fact: "Last recording captured system audio", and a green
`System ✓` chip in the Test Playground. On a machine where the tap silently
fails, the app says it worked.

The mic side of the Test Playground has the same defect in a simpler form —
`TestPlayground.swift:130` uses `micHadAudio: streams.micURL != nil`, which is
the file existing, not audio being in it.

**Fix:** evidence is signal. Peak above a floor, or a proportion of non-silent
frames. Duration is never evidence. This one matters beyond another machine: it
is the check the whole permission story rests on.

## 11.3 — HIGH. Launching can delete a folder that isn't ours

`MinutesApp.swift:78` calls `ModelStorage.adoptLegacyDownloads()` on every
launch. It moves models out of `~/Documents/huggingface`, and then
(`ModelStorage.swift:58`) removes **the whole `~/Documents/huggingface` tree**
when only its `models/argmaxinc/whisperkit-coreml` subtree is empty.

A colleague who does any ML work and has other models cached there loses them,
silently, on first launch. This was safe on exactly one machine.

**Fix:** remove only what we created, and only what we emptied. Never recurse
into a directory we did not write.

## 11.4 — HIGH. The default notes folder may be synced to iCloud

`Preferences.swift:145` defaults to `~/Documents/Minutes`. With iCloud's
*Desktop & Documents* sync enabled — common on managed fleets — every transcript
uploads to iCloud. Meanwhile `SummariesPane.swift:83` tells the user: *"Nothing
about your meetings leaves this Mac — not the audio, not the transcript, not the
summary."*

Both cannot be true. The app is not lying deliberately; it simply does not know.

**Fix:** default outside the synced tree, or detect the sync and say so plainly.
The claim must match the filesystem.

## 11.5 — HIGH. The first meeting downloads 600 MB with no indication

Nothing gates recording on having a model. The first meeting reaches
`WhisperKitTranscriber.swift` with `download: true` and fetches 461–632 MB while
the menu says only "Transcribing meeting…". Offline, it fails after the meeting
is over, when the audio is already captured and the user is already gone.

**Fix:** the model is a prerequisite, announced and confirmed before it is
needed, not discovered during the thing that depends on it.

## 11.6 — MEDIUM. Version, and the absence of one

`Info.plist` hardcodes `1.0` / `1`, and **nothing in `Sources/` reads its own
version** — there is no About surface and no update check. Every bug report from
every colleague, on every future release, would say "1.0".

**Fix:** the version comes from the git tag and is injected at bundle time;
`--doctor` and the window report it. This is a prerequisite for Increment 7, not
a nicety — you cannot ship a second release without it.

## 11.7 — MEDIUM. Smaller, verified, worth doing in the same pass

- **On an M1, the default model may not appear in the picker at all.**
  `Preferences.swift:34` hardcodes a turbo variant verified present *on the
  author's machine*; WhisperKit's supported list is keyed on hardware model. If
  it is absent, the curated list filters it out and the "always offer the active
  model" fallback also fails, leaving four rows with nothing selected. *This one
  I could not verify without an M1 — it depends on a table inside WhisperKit
  1.1.0. It is a strong hypothesis, not a measurement.*
- **"Test your setup — Passed" can pass on a dead microphone** (same root as
  11.2).
- **"Apple Intelligence is switched off on this Mac"** is asserted for every
  unavailable reason, including a model still downloading
  (`SummariesPane.swift:108`); the real reason is received and discarded.
- **Only Slack and Teams 2 are detected** (`DetectionService.swift:39`). Zoom,
  Webex, classic Teams and browser Meet never prompt.
- **No disk-space check anywhere**, with `keepAudio` defaulting to on and audio
  accumulating at roughly 115 MB per hour.
- **`--doctor` prints note filenames**, which are derived meeting titles — and
  the README tells people to share its output. Names and centroids are correctly
  excluded, so this is an inconsistency rather than a design failure.

---

# Increment 7 — One command to install

> **Amended 2026-09-02. Decision taken: no Homebrew, no Developer ID yet.**
>
> The shipped path is a GitHub Release archive plus a one-line installer that
> strips the quarantine attribute. That **is** the Gatekeeper bypass AD-34 was
> written to forbid, so AD-34 was amended in place to say so rather than left
> contradicting what ships. Two costs are accepted rather than solved:
> every update still revokes microphone and system-audio consent (FR-73 stays
> open), and the first install teaches a bypass. Two things keep it honest — the
> installer states what it is doing while it does it, and building from source is
> documented as the path that bypasses nothing, because a locally compiled app is
> never quarantined.
>
> **Revisit when there is more than one or two users**, at which point the
> recurring consent cost exceeds $99/year.
>
> **New measurement that changes the build-from-source option.** Command Line
> Tools alone *cannot* build this app: the `FoundationModels` `@Generable` macro
> plugin ships only inside Xcode. But exactly one file imports
> `FoundationModels`, and stubbing it made a CLT-only release build succeed — so
> a 3.7 GB Xcode prerequisite is caused by one optional feature that already has
> a deterministic fallback. Making it conditional drops the prerequisite to
> `xcode-select --install`. That is now the highest-leverage story in Epic 12.
>
> Measured on a fresh clone: 1 s to clone, 6.2 MB, **67 s** for a clean build,
> bundle and sign, 1.1 GB of build artifacts.

**Epic 12.** Originally gated on the Developer ID decision. Nothing here is speculative
about mechanism; all of it is documented, and the pieces that are not documented
are flagged.

## 12.1 — Signing and notarization in the build

Sign with Developer ID and hardened runtime and a secure timestamp, then:

```sh
ditto -c -k --keepParent Minutes.app Minutes.zip
xcrun notarytool submit Minutes.zip --key … --key-id … --issuer … --wait
xcrun stapler staple Minutes.app        # the .app, never the zip
ditto -c -k --keepParent Minutes.app Minutes-1.0.0.zip
```

Two details worth writing down because they are easy to get wrong:

- **A zip cannot be stapled.** The ticket goes onto the `.app`, which then has to
  be re-zipped. Getting this backwards produces a release that works online and
  fails offline.
- **`altool` is retired** for notarization — the notary service stopped accepting
  it in November 2023. `notarytool` only.

Our existing configuration needs no changes: sandbox off is fine (notarization
does not require it), and `com.apple.security.device.audio-input` is a normal
hardened-runtime entitlement that draws no extra scrutiny.

## 12.2 — Release on a tag, in CI

Push `v0.1.0`, and CI builds, signs, notarizes, staples, packages and publishes
a GitHub Release. Secrets: the `.p12` base64 and its password, a keychain
password, and an **App Store Connect API key** rather than an Apple ID —
preferred for CI because it does not interact with two-factor authentication.

The two failure modes to expect on first run: a keychain that is created but not
unlocked, and a keychain that is not in the search list. Both fail in ways that
look like a signing problem rather than a keychain problem.

## 12.3 — The Homebrew tap

A tap named `NiklasLuettringhaus/homebrew-minutes`, with `Casks/minutes.rb`. The
tap step is not needed — a fully-qualified name auto-taps:

```sh
brew install --cask NiklasLuettringhaus/minutes/minutes
```

That is the one command. The cask carries `depends_on macos: ">= :sequoia"` and
`arch: :arm64`, `uninstall quit: "dev.niklas.minutes"` so upgrades can close a
running menu-bar app cleanly, `livecheck` with `strategy :github_latest`, and a
`zap trash:` covering **all** of the app's footprint (see 13.4 — today's README
undercounts it).

**Official `homebrew/cask` is out of reach for now, and that is fine.** It wants
75 stars or 30 forks or 30 watchers, plus passing Gatekeeper checks. A personal
tap has no such requirement and gives the identical one-line install. Worth
revisiting only if the project gets an audience.

One gap to own: a personal tap has no bot to bump `version` and `sha256` on
release. That is a few lines of CI, not a manual step.

## 12.4 — Apple Silicon only, said out loud

The build is arm64 and every measurement in the repo was taken there. The cask
declares it, and the installer refuses an Intel Mac with a plain sentence rather
than installing something that limps. **If your colleague is on an Intel Mac,
tell me and this changes** — it would need a universal build, and I would want to
actually test whether the CoreML dependencies work on x86_64 before claiming
they do.

---

# Increment 8 — One folder is the whole footprint

**Epic 13.** This is the increment you described: all user data local, in one
place, so working with GitHub is never a worry and the privacy claim is
checkable rather than asserted.

Most of it is already true. Meetings, voices and models are in
`~/Library/Application Support/Minutes/`, and no commit in the history has ever
contained a `.wav`, a `meeting.json` or a `speakers.json`. What is left is the
gap between that and what the README now claims.

## 13.1 — Settings become a document in the same folder

Settings are the odd one out: they live in `~/Library/Preferences/`, so
"delete that folder and Minutes knows nothing about you" is **not currently
true**. A readable `settings.json` beside `speakers.json` makes it true, and
makes the configuration inspectable.

The risk to manage is small and specific: the notes-folder permission is a
security-scoped bookmark, a binary blob. It has to survive the migration, or you
re-pick your folder once. One migration, run once, then UserDefaults is never
read again.

## 13.2 — The app can tell you what it stores about you

A surface listing every path, its size and what it is, with Reveal in Finder.
The privacy claim stops being a sentence in a pane and becomes a list you can
click.

## 13.3 — Export and import the folder

So you can move meetings, voices and settings to a new Mac deliberately.

**One design question this raises, and it needs an answer before the code:** an
export is the first feature in the app's life that lets a voice fingerprint leave
the machine. PRD §9.1 treats it as biometric-adjacent. So export gets its own
opt-in for voices, separate from everything else, and a plain warning — not a
checkbox buried in a sheet. I would rather ask you about the wording than invent
it.

## 13.4 — Uninstall removes everything, and the README stops undercounting

Full removal today requires six things, and the README names three:

```
/Applications/Minutes.app
~/Library/Application Support/Minutes/
~/Library/LaunchAgents/dev.niklas.minutes.login.plist   ← survives deleting the app
~/Library/Preferences/dev.niklas.minutes.plist
the chosen notes folder
tccutil reset Microphone|SystemAudioCaptureRequests dev.niklas.minutes
```

The launch agent is the one that matters: turn on Launch at Login, delete the
app, and macOS keeps trying to start something that is not there. 13.1 removes
one line from this list; the `zap` stanza in 12.3 handles most of the rest.

---

# What I verified, and what I did not

The project's rule is that no measurement is asserted that was not taken, so:

**Measured on this machine**

| Claim | How |
| --- | --- |
| 153 tests pass, 4 skipped, 0 failures | `swift test` |
| The build is clean | `swift build` |
| No user data in any commit, ever | full-history scan for audio, `meeting.json`, `speakers.json`, `centroids.json` |
| The guard catches real user data, including renamed and disguised | staged your actual `speakers.json` as `voices-backup.json` and a real `centroids.json` as `fixture-data.json`; both rejected |
| The guard fires on none of the 366 tracked files | ran it over the tree |
| `--no-quarantine` is gone from Homebrew 6.0.20 | absent from `--help`, rejected as an argument |
| Your 13 meetings are byte-identical after all of today's work | 53 files re-hashed against a manifest taken before I started |
| Every defect in Increment 6 exists at the line given | read the code |

**Documented, not measured**

Apple's Gatekeeper and TCC behaviour, the notarization sequence, Homebrew's cask
rules, and the three first-launch experiences all come from Apple's and
Homebrew's current documentation. **I have not installed this app on a second
Mac.** Until that happens, Increment 7 is a plan built on documentation, and the
first real install will teach us something the documents did not.

**Unverified and flagged**

- The M1 model-picker hypothesis (11.7) needs an M1.
- Whether the ML dependencies build for x86_64 at all (12.4).
- Whether a build-from-source fallback works with Command Line Tools alone or
  needs full Xcode.

# Order, and why

1. **Increment 6 first.** An app that fails silently should not be handed to
   anyone, and 11.6 (version) is a hard prerequisite for releasing twice.
2. **Then the Developer ID**, because it has a purchase and an enrolment in it
   that neither of us controls the timing of. Starting it early means it is not
   the thing everyone waits on.
3. **Increment 7** once the certificate exists.
4. **Increment 8** last. It is the increment with the least urgency and the most
   design in it — and the one design question inside it (13.3, exporting a voice
   fingerprint) deserves a conversation rather than a default.

# What I need from you

- ~~The $99 decision.~~ **Taken: not yet.** Shipping the archive-plus-bypass path
  instead, with the costs recorded above. Revisit at more than one or two users.
- ~~Push access.~~ **Solved** — a fine-grained token for the personal account.
  50 commits pushed, `main` protected, first CI run green on all three jobs.
- **Your colleague's Mac** — Apple Silicon, or Intel? It changes 12.4.
- **Whether an export may include a voice fingerprint at all**, and in what
  words (13.3).
