# Measurement: what a change of audio hardware does to a Session

**2026-09-08. Increment 12. FR-106, AD-60.**

Every figure below has the command that produced it beside it. Recordings are
referred to by duration, never by identifier or title.

---

## Where this came from

Not from this repository. The author reported that switching audio devices during
a call ended the recording and started a new one, with a new prompt. Three
Meeting records from that afternoon carried the evidence:

| | ran | mic device | `outputDeviceChanged` |
|---|---|---|---|
| first | 8m 50s | built-in microphone | **true** |
| second | 35m 50s | AirPods | false |
| third | 24m 59s | AirPods | false |

21 s between the first and second, 46 s between the second and third. One call,
three recordings, three prompts. The evidence existed only because AD-54 stores
the output device on the Meeting and AD-45 stores the declared rate — without
those two the report would have been unfalsifiable.

Read from those records: **the built-in microphone declares 48 kHz and the
AirPods declare 24 kHz.** That single fact decided the shape of the fix, because
it means the ordinary act of putting AirPods in during a call halves the input
rate mid-file, and a repair that only restarted the engine would have written the
rest of the meeting at half speed.

---

## Three causes, not one

### 1. The detector's absence had no hysteresis

`DetectionService.poll()` ran once a second and acted on absence the instant it
saw it:

```swift
let released = firstSeen.keys.filter { !heldIDs.contains($0) }
for id in released {
    firstSeen.removeValue(forKey: id)
    promptedThisSession.remove(id)                                    // re-arms the prompt
    Task { await SessionCoordinator.shared.autoStopIfTriggered(by: id) }   // stops the recording
}
```

Two lines, both halves of the report. To move to new hardware an application must
release one input device and take another, and between the two it holds neither.

There was a **2.5 s debounce entering** a meeting and **none leaving** it. FR-14's
own testable consequence allows *thirty seconds* to notice a meeting has ended.
The implementation spent none of that budget, so this is not a tolerance being
widened — the deadline was always thirty seconds and the code was tighter than
the requirement, in the one direction that loses audio.

### 2. A meeting's identity was the process holding the device

`DetectedMeeting.id` was `bundleID`, and `bundleID` is whichever helper process
was found holding the input device. AD-5 records why prefix *matching* is
mandatory: Teams exposes no bare `com.microsoft.teams2` audio process object,
only `.modulehost`, `.helper` and `.notificationcenter`. But the *state* was
keyed by the full helper ID, and:

- two helpers can hold the device across one call,
- the enumeration order that picks between them is not documented as stable,
- the app swaps between them across a hardware change.

So the identity of a meeting could change while the meeting did not, and a
meeting whose identity changes is indistinguishable from one ending and another
starting. This is the more likely explanation of the second break above, which
carries no device change at all.

### 3. Nothing observed `AVAudioEngineConfigurationChange`

Zero occurrences in the tree. `AVAudioEngine` stops itself when the input
hardware changes and invalidates the tap installed on the input node, so the Mic
Stream silently ended — in a class whose System Stream counterpart has had
`rebuildForDeviceChange` since FR-8.

It went unnoticed because cause 1 was ending the whole Session about two seconds
later anyway. **Fixing either half alone makes the product worse**: the detector
alone gives one long recording with a dead microphone instead of three recordings
that each contain audio. That is why they shipped together.

---

## What the fix measures

`--check-device-switch [seconds] [--before]` records both Streams, sets
`kAudioHardwarePropertyDefaultInputDevice` at the halfway mark, and reports what
survived. `--before` suppresses the rebuild, so the behaviour being replaced has
a command behind it too. The device is restored on every path out, including
failure.

MacBook Pro Microphone → USB PnP Audio Device, both 48 kHz. Mic frames the
device delivered, converted to seconds:

| capture | before | after |
|---|---|---|
| 20 s | 10.0 s | 19.6 s |
| 20 s | 10.2 s | 19.6 s |
| 20 s | **20.0 s** | 19.5 s |
| 16 s | 8.0 s | 15.6 s |
| 16 s | 8.0 s | 15.6 s |
| 16 s | 8.0 s | 15.6 s |
| 16 s | 8.0 s | 15.6 s |
| 16 s | 8.0 s | 15.6 s |

**Seven of eight captures lost the microphone at the instant of the switch, to
the sample** — 384,000 frames of a 16 s capture is exactly half of 48 kHz × 16.
**Eight of eight now survive.**

The one before-run that survived is recorded rather than smoothed. It is PRD Q29,
and it is probably also the reason this survived eleven increments: the fault is
timing-dependent, not certain. It bounds how much of the existing library is
affected, and the signature to count is a Session with `outputDeviceChanged` true
whose Mic Stream is shorter than its System Stream.

### The rate change is proven by fixture, not yet by hardware

No 24 kHz device was connected when this was measured — the three inputs
available were all 48 kHz — so the retune path is covered by a deterministic
fixture rather than by real AirPods:

2 s of 48 kHz followed by 2 s of 24 kHz produces **4.000 s** of 16 kHz file
(`MicDeviceChangeTests`). Converting the second half with the first half's
converter produces 3 s. The file on disk is read back with `AVAudioFile` rather
than trusting the writer's own counter.

**Outstanding:** one real call with AirPods going in mid-meeting. The fixture
cannot tell a correct rate handover from a lucky one on real hardware.

### No regression in what increment 11 fixed

`--check-clock`, same build:

| | previous build | this build |
|---|---|---|
| stream start offset | +14 to +18 ms | **+7 ms** |
| between the two device starts | +0.045 ms | +0.0 ms |
| mic ledger | closes exactly | closes exactly |
| system ledger | closes exactly | closes exactly |
| rate source | audioClock | audioClock |

The audio clock still decides the rate, which was the thing most at risk from
touching the mic capture path.

---

## The uncomfortable finding

While half the meeting was missing, AD-57's ledger read:

```
dropped 0, unaccounted 0, never converted 0, not written 0 in 0 failure(s)
every sample the device reported reached the file
```

It was **right**. The identity answers what became of every sample the device
delivered, and is structurally silent on whether the device kept delivering.
Increment 11 built an instrument to catch a stream losing 0.33% of its samples,
and that instrument could not see a stream losing 50% of its *duration*, because
the samples were never delivered to be lost.

The term that answers it is `deviceFrames` against elapsed time. It was already
recorded, and nothing was reading it that way. This is now a rule in AD-60: a
closed ledger is not evidence that a Stream ran for the whole Session.

---

## What this cost

- **A meeting that ends takes up to 12 s longer to stop**, so up to twelve
  seconds of room noise is recorded after it. Inside FR-14's budget, and cheap
  against losing half a call.
- **AD-44's rate verdict is unavailable on a Session where the device changed
  rate.** Honest, and a real loss of cover, because a wrong rate is precisely the
  fault that produces a recording that looks and reads fine. PRD Q28.
- **A change of channel count is refused**, not absorbed. The Stream ends and
  says why.

## Resource cost, since it was asked

Sampled during a 30 s dual-stream capture, `--check-clock 30`:

| | |
|---|---|
| CPU | **0.2–0.5%** of one core |
| resident memory | **21–32 MB** |

The full app idle after a recording: 0.0% CPU, 366 MB resident. Recording is not
where the machine's time goes. On the machine this was measured on, the load came
from eight orphaned `yes` processes pinning eight of ten cores for four days
(load average 15.0, unrelated to this app) and from 93 MB of free RAM with 9 GB
in the compressor.

---

## Tests

26 added, all device-free.

`DetectionWindowTests` (16) drives the hysteresis with literal clock readings,
including a 9-minute call with a 2-second switch in it, a repeatedly flickering
device, a helper-process swap, and a meeting that genuinely ends. One test
configures **no grace period** and asserts the fault reappears, so the others are
known to be testing something.

`MicDeviceChangeTests` (10) drives the real ring and the real converter with no
audio device: the two-rate duration, the file on disk, samples still in the ring
at the moment of the change, the refused retune, the unavailable rate verdict,
the identity closing across two rates, and the derived form being wrong there.
Two cover the stored shape, because a Meeting recorded before this term existed
must decode as absent rather than as zero.

Suite: **446 tests, 1 failure** — `EnrolmentCalibrationTests`, pre-existing,
byte-identical to base, caused by library data and not by code.
