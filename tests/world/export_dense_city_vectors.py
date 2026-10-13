"""Independent dev5 slot/domain vectors; never invoke the Godot generator."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEFINITION = ROOT / "chapters/chapter_01/city_templates.json"
PRIOR = ROOT / "tests/world/fixtures/NEW-city-vectors-recovery.json"
OUTPUT = ROOT / "tests/world/fixtures/NEW-city-vectors-dense-roofs.json"
PRIOR_SHA256 = "df31557449c4f0227cb9c90461891c99341a47cdf8a86959d1954a1ed05cec40"

def reference():
    assert hashlib.sha256(PRIOR.read_bytes()).hexdigest() == PRIOR_SHA256
    old = json.loads(PRIOR.read_text())
    definitions = json.loads(DEFINITION.read_text())
    vectors = []
    for previous in old["vectors"]:
        seed, chunk = previous["seed"], previous["chunk"]
        domains = {key: hashlib.sha256(f"city_v1|{seed}|{chunk[0]}|{chunk[1]}|{key}".encode()).hexdigest() for key in ("layout", "ground", "decor")}
        template = definitions["templates"][int(domains["layout"][:8], 16) % 4]
        vectors.append({"seed": seed, "chunk": chunk, "template_id": template["template_id"], "ground_variant": int(domains["ground"][:8], 16) % 4, "decor_variant": int(domains["decor"][:8], 16) % 4, "domain_sha256": domains, "prop_ids": sorted(f"city:city_v1:{chunk[0]}:{chunk[1]}:{slot['slot_id']}" for slot in template["slots"])})
    return {"origin_class": "NEW_independent_reference_vectors", "definition_revision": definitions["provenance"]["definition_revision"], "definition_sha256": hashlib.sha256(DEFINITION.read_bytes()).hexdigest(), "method": old["method"], "vectors": vectors, "dense_identity_derivation": {"prior_fixture": "NEW-city-vectors-recovery.json", "prior_fixture_sha256": PRIOR_SHA256, "producer": "tests/world/export_dense_city_vectors.py", "change": "Independent hash-domain recomputation retains old district selection and authors stable visible-terrace slot IDs. Historical recovery and grabber fixtures are unchanged."}}

if __name__ == "__main__":
    encoded = json.dumps(reference(), ensure_ascii=False, indent=2) + "\n"
    if "--check" in sys.argv:
        assert OUTPUT.read_text() == encoded
    else:
        OUTPUT.write_text(encoded)
    print("DENSE_CITY_REFERENCE_OK")
