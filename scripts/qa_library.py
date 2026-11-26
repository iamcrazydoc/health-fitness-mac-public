#!/usr/bin/env python3
"""QA gate for the recovery library: every exercise and running rule must cite a source
that exists in the library, every source needs a PMID and DOI, and media links must be https
from an allowed, trusted host."""
import json, re, sys
from urllib.parse import urlparse

ALLOWED_MEDIA = {"www.nhsinform.scot", "www.nhs.uk", "www.csp.org.uk"}
PHASES = {"calm", "build", "return"}

lib = json.load(open(sys.argv[1]))
errors = []
refs = {r["pmid"]: r for r in lib["refs"]}
for pmid, r in refs.items():
    if not re.fullmatch(r"\d{6,9}", pmid): errors.append(f"bad PMID {pmid}")
    if not r.get("doi", "").startswith("10."): errors.append(f"{pmid}: missing or bad DOI")
    for k in ("authors", "title", "journal", "year", "type"):
        if not r.get(k): errors.append(f"{pmid}: missing {k}")
used = set()
ids = set()
for p in lib["parts"]:
    for r in p["run_refs"] + (p.get("redflag_refs") or []):
        used.add(r)
        if r not in refs: errors.append(f"{p['id']}: running rule cites unknown {r}")
    if not p["exercises"]: errors.append(f"{p['id']}: no exercises")
    for e in p["exercises"]:
        if e["id"] in ids: errors.append(f"duplicate exercise id {e['id']}")
        ids.add(e["id"])
        if e["phase"] not in PHASES: errors.append(f"{e['id']}: bad phase {e['phase']}")
        if not e["refs"]: errors.append(f"{e['id']}: no source")
        for r in e["refs"]:
            used.add(r)
            if r not in refs: errors.append(f"{e['id']}: cites unknown {r}")
        u = urlparse(e["media"])
        if u.scheme != "https" or u.netloc not in ALLOWED_MEDIA: errors.append(f"{e['id']}: media link not from a trusted https host: {e['media']}")
        if not e["steps"] or not e["dose"]: errors.append(f"{e['id']}: missing steps or dose")
unused = set(refs) - used
for r in sorted(unused): print(f"note: source {r} is not cited by anything")
if errors:
    print("\n".join("ERROR: " + e for e in errors)); sys.exit(1)
print(f"OK: {len(lib['parts'])} body parts, {len(ids)} exercises, {len(refs)} sources, all cited and linked.")
