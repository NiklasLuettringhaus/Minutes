#!/usr/bin/env python3
"""Measure transcription accuracy against a reference corpus.

Speed has been measurable in this project since `--benchmark`; accuracy never
has been. Every accuracy claim in `ModelCatalog` — "Highest quality", "English
only, and a little sharper for it" — is an assumption nobody checked. This
scores them.

The corpus is the **AMI Meeting Corpus** (CC BY 4.0), chosen because its two
microphone conditions map onto the two streams Minutes actually records:

  Mix-Headset  each participant's own close mic, mixed — like the far end of a
               video call arriving down the system tap
  Array1-01    one microphone in the middle of the room — like a laptop mic
               with several people around it

Nothing here writes to the repository: audio, references and results all live
under ~/Library/Application Support/MinutesEval (PRD §9.1).

    asr_eval.py reference ES2004a          build the reference transcript
    asr_eval.py score ref.json hyp.json    score one hypothesis
    asr_eval.py sweep --models a,b --sessions ES2004a --mics Mix-Headset
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import time
import xml.etree.ElementTree as ET

EVAL = os.path.expanduser("~/Library/Application Support/MinutesEval")
AMI = os.path.join(EVAL, "ami")
WORDS = os.path.join(AMI, "annotations", "words")
RESULTS = os.path.join(EVAL, "results")
BINARY = os.path.join(os.path.dirname(__file__), "..", "..", ".build", "release", "Minutes")

# ---------------------------------------------------------------- normalisation

# Hesitations are removed from *both* sides. A reference that says "hmm hmm hmm"
# and a transcript that says nothing are not a transcription failure, and
# counting them as three errors would drown the errors that matter.
HESITATION = {
    "hmm", "hm", "mm", "mmm", "mhm", "uh", "um", "uhh", "umm", "er", "erm",
    "ah", "eh", "huh", "oh", "mm-hmm", "uh-huh", "hmmm",
}

ONES = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight",
        "nine", "ten", "eleven", "twelve", "thirteen", "fourteen", "fifteen",
        "sixteen", "seventeen", "eighteen", "nineteen"]
TENS = ["", "", "twenty", "thirty", "forty", "fifty", "sixty", "seventy",
        "eighty", "ninety"]


def number_words(n):
    """Digits to words, so "20" and "twenty" are not counted as an error."""
    if n < 20:
        return ONES[n]
    if n < 100:
        return TENS[n // 10] + ("" if n % 10 == 0 else " " + ONES[n % 10])
    if n < 1000:
        rest = "" if n % 100 == 0 else " " + number_words(n % 100)
        return ONES[n // 100] + " hundred" + rest
    if n < 1_000_000:
        rest = "" if n % 1000 == 0 else " " + number_words(n % 1000)
        return number_words(n // 1000) + " thousand" + rest
    return str(n)


SUBS = [
    (r"[’‘`]", "'"),
    (r"[“”]", '"'),
    (r"&", " and "),
    (r"%", " percent "),
    (r"\bmr\.?\b", "mister"),
    (r"\bokay\b", "ok"),          # the corpus and the models disagree freely
    (r"\balright\b", "all right"),
]


def normalise(text):
    """Lowercase, punctuation-free, hesitation-free word list.

    Apostrophes are dropped rather than expanded ("don't" -> "dont"), which
    collides "we're" with "were" but does so identically on both sides — fair,
    and it removes a whole class of noise that says nothing about accuracy.
    """
    t = text.lower()
    for pattern, repl in SUBS:
        t = re.sub(pattern, repl, t)
    t = re.sub(r"(\d),(\d)", r"\1\2", t)                     # 1,000 -> 1000
    t = re.sub(r"\d+", lambda m: " " + number_words(int(m.group())) + " ", t)
    t = t.replace("'", "")
    t = re.sub(r"[^a-z\s-]", " ", t)
    t = t.replace("-", " ")
    words = [w for w in t.split() if w and w not in HESITATION]
    return words


# ------------------------------------------------------------------- reference

def build_reference(session):
    """One time-ordered word sequence for a whole meeting, from every speaker.

    Punctuation tokens are dropped (the normaliser would remove them anyway).
    Truncated words — "th-", 129 of them across two sessions — are dropped too:
    a fragment no engine can be expected to utter is a guaranteed error that
    measures nothing. `<vocalsound>`, `<disfmarker>` and `<gap>` are not words.
    """
    files = sorted(glob.glob(os.path.join(WORDS, f"{session}.*.words.xml")))
    if not files:
        sys.exit(f"no word annotations for {session} in {WORDS}")
    words, truncated = [], 0
    for path in files:
        speaker = os.path.basename(path).split(".")[1]
        for w in ET.parse(path).getroot():
            if not w.tag.endswith("w"):
                continue
            if w.get("punc") == "true":
                continue
            if w.get("trunc") == "true":
                truncated += 1
                continue
            if not (w.text or "").strip():
                continue
            words.append({
                "start": float(w.get("starttime", 0)),
                "end": float(w.get("endtime", 0)),
                "text": w.text.strip(),
                "speaker": speaker,
            })
    words.sort(key=lambda x: x["start"])
    return {
        "session": session,
        "speakers": sorted({w["speaker"] for w in words}),
        "wordCount": len(words),
        "truncatedDropped": truncated,
        "durationSeconds": max((w["end"] for w in words), default=0),
        "text": " ".join(w["text"] for w in words),
        "words": words,
    }


# ------------------------------------------------------------------------- wer

def levenshtein(ref, hyp):
    """Word-level edit distance, returning (S, D, I) as well as the total."""
    n, m = len(ref), len(hyp)
    # (cost, subs, dels, ins) per cell; two rows is enough.
    prev = [(j, 0, 0, j) for j in range(m + 1)]
    for i in range(1, n + 1):
        cur = [(i, 0, i, 0)] + [None] * m
        for j in range(1, m + 1):
            if ref[i - 1] == hyp[j - 1]:
                cur[j] = prev[j - 1]
            else:
                sub = prev[j - 1]
                dele = prev[j]
                ins = cur[j - 1]
                best = min(sub[0], dele[0], ins[0])
                if best == sub[0]:
                    cur[j] = (sub[0] + 1, sub[1] + 1, sub[2], sub[3])
                elif best == dele[0]:
                    cur[j] = (dele[0] + 1, dele[1], dele[2] + 1, dele[3])
                else:
                    cur[j] = (ins[0] + 1, ins[1], ins[2], ins[3] + 1)
        prev = cur
    total, subs, dels, ins = prev[m]
    return total, subs, dels, ins


def repetition_rate(words, window=12):
    """Share of words inside an immediately repeated n-gram.

    A cheap, model-independent hallucination signal: when an engine loops it
    emits the same phrase over and over, which is exactly what a garbled
    recording produced. Whisper's own decoder uses compression ratio for this;
    this needs no access to logits.
    """
    if len(words) < 2 * window:
        return 0.0
    flagged = [False] * len(words)
    for size in range(3, window + 1):
        for i in range(len(words) - 2 * size + 1):
            if words[i:i + size] == words[i + size:i + 2 * size]:
                for k in range(i, i + 2 * size):
                    flagged[k] = True
    return sum(flagged) / len(words)


# Words a meeting summary does not depend on.
#
# Measured, not assumed: on the first baseline run the most-deleted words were
# "yeah" (38), "ok" (17) and "right" (13) — backchannels spoken *over* whoever
# had the floor, which a single-stream engine drops. They account for a quarter
# of every error. Minutes already strips disfluencies on purpose (FR-31), so
# optimising raw WER would mean chasing words the pipeline deliberately deletes.
#
# `contentWer` therefore scores the words a summary is actually built from.
# Raw WER is still reported, because a metric that only ever flatters the thing
# it measures is not a metric.
BACKCHANNEL = {
    "yeah", "yep", "yes", "no", "ok", "okay", "right", "sure", "exactly",
    "well", "so", "like", "just", "really", "actually", "anyway", "mean",
}
FUNCTION = {
    "a", "an", "the", "and", "or", "but", "if", "then", "than", "as", "at",
    "by", "for", "from", "in", "into", "of", "on", "to", "with", "up", "out",
    "about", "over", "is", "are", "was", "were", "be", "been", "being", "am",
    "do", "does", "did", "dont", "doesnt", "didnt", "have", "has", "had",
    "havent", "hasnt", "will", "would", "wouldnt", "can", "cant", "could",
    "couldnt", "should", "shouldnt", "may", "might", "must", "i", "you", "he",
    "she", "it", "we", "they", "me", "him", "her", "us", "them", "my", "your",
    "his", "its", "our", "their", "this", "that", "these", "those", "thats",
    "there", "theres", "here", "what", "which", "who", "when", "where", "how",
    "not", "very", "too", "also", "get", "got", "go", "going", "gonna",
    "wanna", "know", "think", "one", "some", "any", "all",
}
LOW_INFORMATION = BACKCHANNEL | FUNCTION


def content_words(words):
    return [w for w in words if w not in LOW_INFORMATION]


def recall(reference_tokens, hypothesis_words):
    """Share of distinct reference tokens that appear anywhere in the output.

    Deliberately position-free. A name recognised but attached to the wrong
    moment is a diarisation problem, not a transcription one, and conflating
    the two would hide both.
    """
    if not reference_tokens:
        return None
    present = set(hypothesis_words)
    hit = sum(1 for t in set(reference_tokens) if t in present)
    return hit / len(set(reference_tokens))


def score(reference_text, hypothesis_text, reference_words=None):
    ref = normalise(reference_text)
    hyp = normalise(hypothesis_text)
    if not ref:
        sys.exit("reference is empty after normalisation")
    total, subs, dels, ins = levenshtein(ref, hyp)

    ref_content, hyp_content = content_words(ref), content_words(hyp)
    c_total, c_subs, c_dels, c_ins = levenshtein(ref_content, hyp_content)

    out = {
        "refWords": len(ref),
        "hypWords": len(hyp),
        "wer": total / len(ref),
        "substitutions": subs,
        "deletions": dels,
        "insertions": ins,
        "deletionRate": dels / len(ref),
        "insertionRate": ins / len(ref),
        "refContentWords": len(ref_content),
        "contentWer": c_total / len(ref_content) if ref_content else None,
        "contentDeletionRate": c_dels / len(ref_content) if ref_content else None,
        "contentSubstitutionRate": c_subs / len(ref_content) if ref_content else None,
        "repetitionRate": repetition_rate(hyp),
    }

    # Proper nouns and numbers, the two things a summary cannot paraphrase past.
    # A wrong name or a wrong figure is the error a reader actually notices.
    if reference_words:
        names, numbers = [], []
        for i, w in enumerate(reference_words):
            raw = w["text"].strip()
            if re.fullmatch(r"\d[\d.,]*", raw):
                numbers.extend(normalise(raw))
            elif raw[:1].isupper() and i > 0 and len(raw) > 1:
                token = normalise(raw)
                if token and token[0] not in LOW_INFORMATION:
                    names.append(token[0])
        out["properNouns"] = len(set(names))
        out["properNounRecall"] = recall(names, hyp)
        out["numberTokens"] = len(set(numbers))
        out["numberRecall"] = recall(numbers, hyp)
    return out


# ----------------------------------------------------------------------- sweep

def transcribe(audio, model, out_path):
    """Runs the app's own `--asr` so the harness measures the shipping path."""
    started = time.time()
    proc = subprocess.run(
        [os.path.abspath(BINARY), "--asr", audio, "--model", model, "--out", out_path],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return None, (proc.stderr or proc.stdout).strip()[:400]
    with open(out_path) as f:
        return json.load(f), None


def sweep(models, sessions, mics):
    os.makedirs(RESULTS, exist_ok=True)
    rows = []
    for session in sessions:
        ref = build_reference(session)
        ref_path = os.path.join(RESULTS, f"reference-{session}.json")
        with open(ref_path, "w") as f:
            json.dump(ref, f)
        print(f"\n{session}: {ref['wordCount']} reference words, "
              f"{len(ref['speakers'])} speakers, "
              f"{ref['durationSeconds'] / 60:.1f} min")
        for mic in mics:
            audio = os.path.join(AMI, f"{session}.{mic}.wav")
            if not os.path.exists(audio):
                print(f"  missing audio: {audio}")
                continue
            for model in models:
                tag = f"{session}.{mic}.{model}"
                hyp_path = os.path.join(RESULTS, f"hyp-{tag}.json")
                result, err = transcribe(audio, model, hyp_path)
                if err:
                    print(f"  {mic:12} {model:46} FAILED {err}")
                    continue
                text = " ".join(s["text"] for s in result["segments"])
                s = score(ref["text"], text, ref["words"])
                row = dict(session=session, mic=mic, model=model,
                           rtf=result["realtimeFactor"],
                           segments=result["segmentCount"], **s)
                rows.append(row)
                print(f"  {mic:12} {model:44} "
                      f"WER {s['wer'] * 100:5.1f}%  "
                      f"content {s['contentWer'] * 100:5.1f}%  "
                      f"names {s['properNounRecall'] * 100:4.0f}%  "
                      f"nums {(s['numberRecall'] or 0) * 100:4.0f}%  "
                      f"rep {s['repetitionRate'] * 100:4.1f}%  "
                      f"x{result['realtimeFactor']:.3f}")
    out = os.path.join(RESULTS, "sweep.json")
    existing = []
    if os.path.exists(out):
        with open(out) as f:
            existing = json.load(f)
    with open(out, "w") as f:
        json.dump(existing + rows, f, indent=2)
    print(f"\n{len(rows)} results appended to {out}")
    return rows


def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("reference")
    r.add_argument("session")

    sc = sub.add_parser("score")
    sc.add_argument("reference")
    sc.add_argument("hypothesis")

    sw = sub.add_parser("sweep")
    sw.add_argument("--models", required=True)
    sw.add_argument("--sessions", default="ES2004a")
    sw.add_argument("--mics", default="Mix-Headset,Array1-01")

    a = p.parse_args()
    if a.cmd == "reference":
        ref = build_reference(a.session)
        os.makedirs(RESULTS, exist_ok=True)
        path = os.path.join(RESULTS, f"reference-{a.session}.json")
        with open(path, "w") as f:
            json.dump(ref, f)
        print(f"{ref['wordCount']} words, {len(ref['speakers'])} speakers, "
              f"{ref['durationSeconds'] / 60:.1f} min -> {path}")
        print(f"dropped {ref['truncatedDropped']} truncated fragments")
    elif a.cmd == "score":
        with open(a.reference) as f:
            ref = json.load(f)
        with open(a.hypothesis) as f:
            hyp = json.load(f)
        text = " ".join(s["text"] for s in hyp["segments"]) \
            if "segments" in hyp else hyp["text"]
        print(json.dumps(score(ref["text"], text, ref["words"]), indent=2))
    else:
        sweep(a.models.split(","), a.sessions.split(","), a.mics.split(","))


if __name__ == "__main__":
    main()
