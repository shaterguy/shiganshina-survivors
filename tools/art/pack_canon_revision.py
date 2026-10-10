"""Pack inspected revision candidates without publishing the runtime manifest."""
import hashlib
import json
import pathlib
import tempfile
import sys
import pack_atlases as pack

ROOT = pathlib.Path(__file__).resolve().parents[2]
CANDIDATES = ROOT / 'docs/art/canon-v2-candidates.json'

def prepare(asset_id, source):
    current = json.loads((ROOT / 'assets/manifest.json').read_text())
    old = current['assets'][asset_id]
    with tempfile.TemporaryDirectory(prefix='shiganshina-canon-') as tmp:
        manifest = pathlib.Path(tmp) / 'manifest.json'
        manifest.write_text(json.dumps(current))
        pack.M = manifest
        path = pathlib.Path(pack.pack_character(asset_id + '_v2', source,
                                               (old['cell_w'], old['cell_h'])))
        rec = json.loads(manifest.read_text())['assets'][asset_id + '_v2']
    # The gameplay state contract remains stable while the actual file is versioned.
    rec['animations'] = old['animations']
    rec['art_revision'] = 2
    rec['review_status'] = 'candidate_pending_integrator_visual_review'
    rec['source_method'] = 'Original built-in image edit of the original sheet; canonical unclothed nonsexual adult Titan design correction; nearest-neighbor shared-palette packing.'
    if 'defeatable' in old:
        rec['defeatable'] = old['defeatable']
    rec['sha256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    data = json.loads(CANDIDATES.read_text()) if CANDIDATES.exists() else {}
    data[asset_id] = rec
    CANDIDATES.write_text(json.dumps(data, indent=2) + '\n')
    return rec

if __name__ == '__main__':
    print(json.dumps(prepare(sys.argv[1], sys.argv[2]), indent=2))
