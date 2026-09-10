#!/usr/bin/env python3
"""Decompose each instrumented recording into start offset and unwritten audio.

The two faults increment 11 exists for were being read as one number — the
difference in length between mic.wav and system.wav. This separates them, using
only the device's own frame counts (AD-51) against the file on disk:

    seconds the device counted  -  seconds in the file  =  audio never written

and the start offset the two Streams' first host times give (FR-97, AD-53).

Needs a Meeting recorded by increment 10 or later; earlier records carry no
rate or continuity block and are skipped rather than guessed at.

Prints durations, rates and percentages only — never a meeting ID, a title or a
path (PRD Section 9.1). The library lives outside the repository.

    ./Scripts/decompose-capture.py
"""
import json, os, glob

LIB = os.path.expanduser("~/Library/Application Support/Minutes/Meetings")
WAV_HEADER = 44          # canonical 44-byte header as AVAudioFile writes it
BYTES_PER_FRAME = 2      # 16-bit mono
OUT_RATE = 16000


def file_seconds(path):
    return (os.path.getsize(path) - WAV_HEADER) / BYTES_PER_FRAME / OUT_RATE


def device_seconds(rate, continuity):
    """Seconds of input the device's own counter accounted for.

    `expectedFrames` is the sample-time advance, which by construction stops at
    the last callback's *start*, so that callback's own frames are added back.
    The effective rate is the corrected one where AD-44 corrected it.
    """
    effective = rate.get("correctedTo") or rate["declaredRate"]
    frames = continuity["expectedFrames"] + (rate.get("callbackFrames") or 0)
    return frames / effective


rows = []
for d in sorted(glob.glob(os.path.join(LIB, "*"))):
    mic, sysm = os.path.join(d, "mic.wav"), os.path.join(d, "system.wav")
    if not (os.path.exists(mic) and os.path.exists(sysm)):
        continue
    try:
        m = json.load(open(os.path.join(d, "meeting.json")))
    except Exception:
        continue
    mr, sr = m.get("micRate"), m.get("systemRate")
    mc, sc = m.get("micContinuity"), m.get("systemContinuity")
    if not (mr and sr and mc and sc and mc.get("expectedFrames")):
        continue
    mf, sf = file_seconds(mic), file_seconds(sysm)
    me, se = device_seconds(mr, mc), device_seconds(sr, sc)
    dev = (m.get("outputDevice") or {}).get("name")
    # A device *model* is hardware and not meeting content, but a device the user
    # named after themselves is a name. Report the kind instead.
    kind = (m.get("outputDevice") or {}).get("kind", "?")
    rows.append((mf / 60, kind, m.get("streamStartOffset"),
                 me - mf, (me - mf) / me * 100,
                 se - sf, (se - sf) / se * 100,
                 mr.get("callbackFrames"), sr.get("callbackFrames")))

rows.sort(key=lambda r: r[0])
print(f"{'minutes':>8} {'output':>13} {'offset':>9} | "
      f"{'mic short':>10} {'mic %':>8} {'cb':>5} | {'sys short':>10} {'sys %':>8} {'cb':>5}")
for mins, kind, off, ms, mp, ss, sp, mcb, scb in rows:
    o = f"{off * 1000:+.0f} ms" if off is not None else "unknown"
    print(f"{mins:8.1f} {kind:>13} {o:>9} | "
          f"{ms:9.2f}s {mp:+7.3f}% {mcb or 0:5d} | {ss:9.2f}s {sp:+7.3f}% {scb or 0:5d}")
print(f"\n{len(rows)} recording(s) carry the counters this needs")
