#!/usr/bin/env python3
"""Mic-minus-system length for every dual-stream recording in the local library.

The table increment 11 was built from, and the reason its entering hypothesis
died: a 50.3-minute recording shows 0.00% drift and a 31.6-minute one shows
0.37%, so the loss is not proportional to duration and is not a constant
per-call cost.

Prints durations and rates only — never a meeting ID, a title or a path (PRD
Section 9.1). The library lives outside the repository and this reads it in
place.

    ./Scripts/measure-stream-drift.py
"""
import os, struct, sys, json, glob

LIB = os.path.expanduser("~/Library/Application Support/Minutes/Meetings")

def wav_info(p):
    with open(p, "rb") as f:
        d = f.read(12)
        if len(d) < 12 or d[:4] != b"RIFF": return None
        rate = ch = bits = None; datalen = None
        while True:
            h = f.read(8)
            if len(h) < 8: break
            cid, sz = h[:4], struct.unpack("<I", h[4:8])[0]
            if cid == b"fmt ":
                b = f.read(sz)
                ch = struct.unpack("<H", b[2:4])[0]
                rate = struct.unpack("<I", b[4:8])[0]
                bits = struct.unpack("<H", b[14:16])[0]
            elif cid == b"data":
                datalen = sz
                f.seek(sz + (sz & 1), 1)
            else:
                f.seek(sz + (sz & 1), 1)
        if not rate or not datalen: return None
        frames = datalen // (ch * bits // 8)
        return dict(rate=rate, ch=ch, bits=bits, frames=frames, seconds=frames / rate)

rows = []
for d in sorted(glob.glob(os.path.join(LIB, "*"))):
    m, s = os.path.join(d, "mic.wav"), os.path.join(d, "system.wav")
    if not (os.path.exists(m) and os.path.exists(s)): continue
    mi, si = wav_info(m), wav_info(s)
    if not mi or not si: continue
    diff = mi["seconds"] - si["seconds"]
    rows.append((mi["seconds"]/60, diff, diff/mi["seconds"]*100 if mi["seconds"] else 0,
                 mi["rate"], si["rate"], mi["frames"], si["frames"]))

rows.sort(key=lambda r: r[0])
print(f"{'minutes':>8} {'mic s':>9} {'sys s':>9} {'mic-sys':>9} {'drift%':>8} {'micHz':>6} {'sysHz':>6}")
for mins, diff, pct, mr, sr, mf, sf in rows:
    print(f"{mins:8.1f} {mf/mr:9.2f} {sf/sr:9.2f} {diff:+9.2f} {pct:+8.3f} {mr:6d} {sr:6d}")
print(f"\n{len(rows)} dual-stream recordings")
n16 = [r for r in rows if r[3] == 16000 and r[4] == 16000]
print(f"{len(n16)} at 16 kHz on both streams (comparable; rate-repaired ones have rewritten headers)")
if n16:
    worst = max(n16, key=lambda r: abs(r[1]))
    print(f"worst 16 kHz drift: {worst[1]:+.2f} s over {worst[0]:.1f} min ({worst[2]:+.3f}%)")
