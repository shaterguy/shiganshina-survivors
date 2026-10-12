"""Regenerate independent current-city vectors without calling the game generator."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFINITION = ROOT / "chapters/chapter_01/city_templates.json"
PRIOR = ROOT / "tests/world/fixtures/NEW-city-vectors-recovery.json"
OUTPUT = ROOT / "tests/world/fixtures/NEW-city-vectors-grabber.json"
PRIOR_SHA256 = "df31557449c4f0227cb9c90461891c99341a47cdf8a86959d1954a1ed05cec40"
assert hashlib.sha256(PRIOR.read_bytes()).hexdigest() == PRIOR_SHA256
prior = json.loads(PRIOR.read_text())
definition = json.loads(DEFINITION.read_text())
assert definition["content_revision"] == "ch01.3-rebuild.7-grabber-hand"
vectors = []
for previous in prior["vectors"]:
    seed, chunk = previous["seed"], previous["chunk"]
    domain = {
        key: hashlib.sha256(f"city_v1|{seed}|{chunk[0]}|{chunk[1]}|{key}".encode()).hexdigest()
        for key in ("layout", "ground", "decor")
    }
    template = definition["templates"][int(domain["layout"][:8], 16) % len(definition["templates"])]
    vectors.append({
        "seed": seed, "chunk": chunk, "template_id": template["template_id"],
        "ground_variant": int(domain["ground"][:8], 16) % 4,
        "decor_variant": int(domain["decor"][:8], 16) % 4,
        "domain_sha256": domain,
        "prop_ids": sorted(f"city:city_v1:{chunk[0]}:{chunk[1]}:{slot['slot_id']}" for slot in template["slots"]),
    })
# The content revision changed, not the authored district layout or domain rules.
assert vectors == prior["vectors"]
result = {
    "origin_class": "NEW_independent_reference_vectors",
    "definition_revision": definition["provenance"]["definition_revision"],
    "definition_sha256": hashlib.sha256(DEFINITION.read_bytes()).hexdigest(),
    "method": prior["method"],
    "vectors": vectors,
    "grabber_identity_derivation": {
        "prior_fixture": "NEW-city-vectors-recovery.json",
        "prior_fixture_sha256": PRIOR_SHA256,
        "producer": "tests/world/export_grabber_city_vectors.py",
        "change": "Recomputed all domain digests, variants and sorted prop IDs from current definitions; values equal preserved prior vectors. Current definition bytes hash is new.",
    },
}
OUTPUT.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
assert json.loads(OUTPUT.read_text()) == result
assert hashlib.sha256(PRIOR.read_bytes()).hexdigest() == PRIOR_SHA256
print(f"CITY_VECTOR_EXPORT vectors={len(vectors)} failures=0 prior_unchanged=true definition_sha256={result['definition_sha256']}")
