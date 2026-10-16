"""Future offline comparison of captures produced by the SAME GDScript harness.
Run only after authorized baseline and integrated captures. Does not run Godot.
"""
import argparse
import hashlib
import json
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("--baseline-source-sha", required=True)
    parser.add_argument("--candidate-source-sha", required=True)
    args = parser.parse_args()
    for sha in (args.baseline_source_sha, args.candidate_source_sha):
        if len(sha) != 40 or any(c not in "0123456789abcdef" for c in sha):
            raise SystemExit("exact 40-character source commit SHAs required")
    expected = ["initial"] + [f"move:{i}" for i in range(180)] + ["legacy_boss_offer", "legacy_boss_choice"]
    captures = []
    for path in (args.baseline, args.candidate):
        value = json.loads(path.read_text())
        if value.get("format") != "loot-legacy-capture-v1" or value.get("failures") != []:
            raise SystemExit(f"invalid or failed capture: {path}")
        if [row.get("label") for row in value.get("rows", [])] != expected:
            raise SystemExit(f"incomplete/reordered trace: {path}")
        captures.append(value)
    different = [a["label"] for a, b in zip(captures[0]["rows"], captures[1]["rows"]) if a != b]
    print(json.dumps({"ok": not different, "comparison": "legacy finite full-state/events/RNG/offer trace",
                      "baseline_source_sha": args.baseline_source_sha,
                      "candidate_source_sha": args.candidate_source_sha,
                      "baseline_capture_sha256": hashlib.sha256(args.baseline.read_bytes()).hexdigest(),
                      "candidate_capture_sha256": hashlib.sha256(args.candidate.read_bytes()).hexdigest(),
                      "different_labels": different}, indent=2))
    raise SystemExit(1 if different else 0)

if __name__ == "__main__":
    main()
