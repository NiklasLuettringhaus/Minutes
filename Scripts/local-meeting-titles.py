#!/usr/bin/env python3
"""Prints the meeting titles held in the *local* library, one per line.

Story 13.5. The structural guard keeps audio, records and embeddings out of the
repository by path and by shape, and it works. It cannot see a real meeting title
quoted in a design document or borrowed for a UI fixture — and by the time that
was noticed the repository was public and two committed files carried real titles.
A meeting title is meeting content (PRD §9.1).

This is local-only by construction: knowing what a real title looks like requires
the user's library, and CI does not have one. The output is piped straight into
grep and is **never written to a file in the repository** — a list of what must
not be committed would itself be the leak.
"""
import json
import os
import re
import sys

# Single common words are excluded. Real auto-titles include "Sorry", "What" and
# "Die", and refusing every commit that contains those words would produce a
# check people switch off. A multi-word title, or a long distinctive single word,
# is specific enough to be worth blocking.
MIN_SINGLE_WORD = 12


def titles(library: str) -> set[str]:
    out: set[str] = set()
    if not os.path.isdir(library):
        return out
    for entry in sorted(os.listdir(library)):
        record = os.path.join(library, entry, "meeting.json")
        if not os.path.exists(record):
            continue
        try:
            with open(record, encoding="utf-8") as fh:
                meeting = json.load(fh)
        except (OSError, ValueError):
            continue
        candidates = [(meeting.get("metadata") or {}).get("title"),
                      meeting.get("noteFilename")]
        for candidate in candidates:
            if not candidate:
                continue
            # A note filename is a date prefix, a slug and an extension; the
            # meaningful part is the slug.
            candidate = re.sub(r"^\d{4}-\d{2}-\d{2} \d{4} ", "", candidate)
            candidate = re.sub(r"\.md$", "", candidate)
            candidate = candidate.replace("-", " ").strip()
            if not candidate:
                continue
            words = candidate.split()
            if len(words) == 1 and len(candidate) < MIN_SINGLE_WORD:
                continue
            out.add(candidate)
    return out


if __name__ == "__main__":
    library = sys.argv[1] if len(sys.argv) > 1 else os.path.expanduser(
        "~/Library/Application Support/Minutes/Meetings")
    for t in sorted(titles(library)):
        print(t)
