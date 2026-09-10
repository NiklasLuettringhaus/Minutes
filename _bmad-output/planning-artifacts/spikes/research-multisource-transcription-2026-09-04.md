# Research: transcribing a meeting from two audio sources

**Date:** 2026-09-04
**Question:** what actually improves transcription quality when the audio comes
from more than one source, and what does the field already know about the
problems we hit?
**Method:** published literature and benchmark results, read against the
measurements already taken on our own recordings
(`investigation-transcription-quality-2026-09-03.md`,
`calibration-echo-threshold-2026-09-03.md`).

---

## 0. What we are actually building, in the field's vocabulary

Minutes records **two asynchronous streams of different kinds**: a close
microphone (the room) and a system tap (the far end of a call, already mixed).
That is not the configuration most of the literature studies. The benchmarks
assume either one far-field array (CHiME/NOTSOFAR) or one close mic per
participant (AMI headsets). Our shape — one near mic plus a clean electrical
copy of the remote audio — is closest to the **acoustic-echo-cancellation**
setting from telephony, and that turns out to be the more useful lens.

Two consequences run through everything below:

- The remote audio reaches us **twice**: once electrically (perfect) and once
  acoustically through the loudspeakers (delayed, distorted). That is an echo
  problem, not a diarisation problem.
- We have a **reference signal**. Almost every technique that needs to know
  "who is the far end" is cheaper for us than for a system with only
  microphones, because we can simply look at the tap.

---

## 1. The echo is a known category problem, and we are solving it the hard way

### It is standard, and named

Recall.ai, who sell meeting-capture infrastructure, put it plainly: echo
"occurs when a microphone input picks up audio that is also being played
through the speakers, resulting in duplicated speech getting recorded," and it
is "**a challenge every developer building a meeting recorder needs to
solve**." Their recommended solution is the one the field has used for decades:
an **AEC library that takes both the system audio and the microphone** and
removes the overlap from the mic stream.

That is exactly the defect I measured on your library — 3 of 12 recordings, up
to 58% of microphone words duplicated — arrived at independently, which is
reassuring about the diagnosis and unflattering about the reading I had done
first.

### The operating system will not do it for us

The obvious hope was Apple's voice-processing audio unit
(`kAudioUnitSubType_VoiceProcessingIO`), which does AEC in the OS. **It cannot
help us**, and the reason is structural: VPIO's echo reference is *its own
output bus*, fed by the app's render callback. It "can only cancel echoes from
audio it directly produces." Teams plays the meeting audio, not us, so VPIO has
nothing to subtract. Two secondary blockers confirm the direction is closed:
`AVAudioEngine` cannot be retargeted to a tap-backed aggregate device at all
(which is our AD-1 finding, independently reported), and VPIO also applies AGC
and noise suppression we have not evaluated for transcription.

**So if we want AEC, we implement it, with the tap as the reference.** That is
what the category does.

### My "cancellation is impossible" finding needs qualifying

I measured the upper bound on **linear** cancellation at 8.7–10.6 dB against
the 20–40 dB a useful canceller needs, and concluded cancellation could not
work. That measurement stands, and the conclusion was too broad.

Real cancellers are not purely linear. WebRTC's AEC3 — the default in every
Chrome-based call — is a **linear adaptive filter followed by a non-linear
residual-echo suppressor**, with a double-talk detector that freezes adaptation
when both sides speak. The residual stage exists precisely because "the
nonlinear residual-echo suppressor is important on cheap laptop and phone
hardware where speakers distort," which is our case. AEC3 is also explicitly
built to handle "delay changes, clock drift, and double-talk," all three of
which my static-offset approach handles badly or not at all.

Two further things I had backwards:

- **AEC belongs at capture time**, where the reference is aligned by
  construction and the filter adapts continuously. I ran it post hoc on two
  independently-clocked files, which is the hardest possible version of the
  problem — and is why I found a 920 ms offset and length differences up to
  3.3 s.
- **For transcription we do not need clean audio, we need the echo not to be
  transcribed.** A residual suppressor that heavily attenuates echo-dominated
  bands is sufficient even if the result sounds poor.

### There is a much better gate than the one I built

I gate on a correlation statistic calibrated across three recordings. The
category's answer is simpler and more reliable: **detect the output device.**
Recall.ai: "echo isn't a problem with headphones," so "your application needs
logic to detect the output device type and accordingly enable or disable AEC."

We already listen for default-output-device changes (`SystemTapCapture` has the
property listener). Headphones versus loudspeakers is a fact we can read,
not a threshold we have to tune — and it explains our data exactly: every clean
recording was on headphones, every affected one was not.

They also warn that "there is no one size fits all solution... you need to test
it with your actual pipeline," which is what the harness now makes possible.

---

## 2. Where meeting-transcription accuracy actually comes from

The relevant benchmark is the **CHiME-8 DASR / NOTSOFAR-1** challenge: real
office meetings, 4–8 speakers, transcribed and diarised from distant
microphones. Findings that bear on us:

**The winning architecture is diarisation → separation → ASR.** The multi-channel
track was won by USTC with a "Dia-Sep-ASR" pipeline, and second and third
(STCON, NTT) used the same structure — "it is evident that this paradigm
dominates." Speaker information is computed *first* and then used to condition
everything downstream. Our pipeline is the opposite order: we transcribe, then
diarise, then attribute.

**Diarisation quality beats ASR quality.** The challenge paper's own summary:
"diarisation improvements yield larger WER reductions than incremental ASR gains
alone," and "ASR performance alone cannot compensate for poor upstream
separation or speaker identification." This is the single most useful sentence
in the literature for us, because it says the afternoon I spent measuring ASR
models was measuring the wrong thing — and it is consistent with what those
measurements found, which was that no model choice available to us pays.

**Guided source separation needs channels we do not have.** GSS contributes
3–5 WER points on overlapped segments, but it is a microphone-array technique:
going from two channels to seven gave relative WER reductions of **50.4% on
LibriCSS and 21.8% on AMI**. At two channels — and ours are not even a
coherent array, being one mic and one electrical feed — the gain is much
smaller. GSS "has seen limited adoption for meeting transcription benchmarks
primarily due to its high computation time" as well.

**A calibration note, so these numbers are not misread.** Best systems reach
roughly 15–18% WER on AMI, against our 22.6% pooled on close mics. **Those are
not comparable figures.** The challenge reports speaker-attributed error
(cpWER/tcpWER) over far-field arrays with diarisation included; I measured
plain, speaker-agnostic word error on a pre-mixed headset channel, which is an
easier metric on easier audio. The honest reading is only directional: we are in
a plausible range, and the headroom the field found came from diarisation and
separation rather than from swapping recognisers.

---

## 3. Our dominant error is deletions — and the obvious fix does not fix it

Measured at baseline: **290 deletions against 87 substitutions and 28
insertions**, led by `yeah` (38), `ok` (17), `right` (13) — backchannels spoken
over whoever had the floor.

**Voice-activity segmentation will not help this.** It is the standard
long-form recommendation and it is well evidenced — VAD before Whisper cut WER
from 0.675 to 0.419 in one study, mostly by stopping the model hallucinating
over silence. But the mechanism is wrong for us: RMS-VAD "has **no significant
effect on deletion rates**, however it does reduce insertion errors." We have
almost no insertion or hallucination problem left on clean recordings
(insertions 1.1%, repetition 0.5% median). So VAD is a fix for a problem we
already fixed a different way in increment 8.

**The lever for deletions is overlap handling.** The challenge systems address
exactly this with **overlap-aware diarisation** and **target-speaker VAD**:
TS-VAD "predicts per-frame speech activities for speakers simultaneously, which
directly handles overlapping problems," and it is what the top teams adopted
because meeting corpora "have a high ratio of speaker overlap." The 2025
follow-on work is on joint target-speaker ASR and activity detection.

**We can reach this without a new dependency.** FluidAudio, which we already
ship, includes `sortformer` (streaming diarisation) and `ls-eend` — end-to-end
neural diarisers, which are overlap-aware by construction, unlike the
clustering diariser we use now. One caution already recorded: the `ls-eend`
variant is *tuned on AMI*, so it cannot be honestly evaluated on our AMI-based
harness; a different corpus would be needed to score it.

---

## 4. The fix for the diarisation failure I measured

Yesterday's result: muting the echo before clustering made the speaker count
**worse** (5→7, 6→6, 3→5). Muting punches silence through continuous speech, so
one voice arrives as fragments and the clusterer splits it.

The literature points at the alternative directly. Clustering diarisation works
by extracting a speaker embedding per segment and grouping them, and the
standard vocabulary includes **cluster removal** — deciding after clustering
that a cluster does not correspond to a speaker who should be there. The
enrolment-free target-extraction line of work does the same thing by predicting
per-speaker embeddings from the mixture and using them as a control signal.

For us this is unusually cheap, because **we have the far end on its own
channel.** So:

1. Diarise the microphone stream **unmodified** — no fragmentation.
2. Extract speaker embeddings from the **system** stream: these are, by
   construction, the people who are not in the room.
3. Drop or relabel any microphone cluster that matches one of them.

This never damages audio, never splits a voice, and uses the reference signal we
already have. It is also the same machinery as our existing enrolment feature
(FR-63, AD-30, AD-31 already define an embedding-distance threshold and its
measured separation), pointed at the opposite question: instead of "which voice
is the user", "which voices are demonstrably not in the room".

---

## 5. What this implies, ranked by evidence

1. **Detect the output device and cancel at capture.** Replace my correlation
   gate with a fact (headphones vs speakers), and run a real AEC — linear filter
   plus non-linear residual suppression, with the tap as reference — inside the
   Session where the reference is aligned and adaptation is continuous. This is
   what the category does, and it removes the echo before any consumer sees it,
   which is what AD-47 wanted and my post-hoc version only half delivered.
   Keep the post-hoc detector for recordings already on disk.
2. **Filter clusters, not audio (§4).** Directly replaces the approach my own
   measurement refuted, and needs no new models.
3. **Move to overlap-aware diarisation** (`sortformer` / EEND), because
   diarisation is where the field's WER gains came from and overlap is where our
   errors are. Needs a corpus that is not AMI to score honestly.
4. **Consider reordering the pipeline to diarise before transcribing**, which is
   what every top challenge system does. This is a real architectural change and
   should not be undertaken on the strength of one paper summary.

**Not supported by this research** — and each of these was a candidate before
it:

- **VAD segmentation** — no effect on deletions, which is our error profile.
- **Guided source separation** — an array technique; two channels give a
  fraction of the benefit, at high cost.
- **Apple's VoiceProcessingIO** — structurally cannot see another app's output.
- **Swapping the recogniser** — already measured: nothing available to us pays,
  and the literature agrees the gains are upstream of the recogniser.

---

## 6. Limits of this research

- It is literature and vendor documentation, not experiments. Every number in
  §2 and §3 comes from someone else's corpus and metric; only §1's diagnosis and
  §3's error profile are measured on our own audio.
- The AEC recommendation is **not yet measured for us**. The one thing I did
  measure — the linear bound at ~10 dB — says the linear stage alone is
  insufficient, and the non-linear stage's value on our recordings is an
  assumption until tested. That test is cheap now: feed both streams through a
  candidate AEC, re-transcribe, score with the harness.
- The benchmark comparison in §2 is directional only, for the metric reasons
  stated there. I have deliberately not written "we are N points behind the
  state of the art", because the measurement to support that has not been made.
- Nothing here evaluates the non-English case, and our hardest AMI session is
  its non-native-speaker set (§13 Q21). The field's meeting benchmarks are
  overwhelmingly English.
