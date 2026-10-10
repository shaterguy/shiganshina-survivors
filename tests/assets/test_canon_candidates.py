"""Read-only candidate checks; visual/canon review is intentionally separate."""
from pathlib import Path
import hashlib
import json
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
manifest = json.loads((ROOT / 'assets/manifest.json').read_text())
candidates = json.loads((ROOT / 'docs/art/canon-v2-candidates.json').read_text())
palette = {tuple(bytes.fromhex(c[1:])) for c in manifest['palette']}
checks = 0
for aid, asset in candidates.items():
    path = ROOT / asset['path'][6:]
    image = Image.open(path)
    assert image.mode == 'RGBA', aid
    assert image.size == (asset['width'], asset['height']), aid
    assert hashlib.sha256(path.read_bytes()).hexdigest() == asset['sha256'], aid
    assert asset['anchor_px'] == [asset['cell_w'] // 2, asset['cell_h']], aid
    assert {p[:3] for p in image.get_flattened_data() if p[3]} <= palette, aid
    assert {p[3] for p in image.get_flattened_data()} <= {0, 255}, aid
    checks += 6
    for animation in asset['animations'].values():
        for frame in animation['frames']:
            x = frame % asset['columns'] * asset['cell_w']
            y = frame // asset['columns'] * asset['cell_h']
            region = image.crop((x, y, x + asset['cell_w'], y + asset['cell_h']))
            assert region.getchannel('A').getbbox(), (aid, frame)
            checks += 1
    frames = []
    for frame in asset['animations']['move']['frames']:
        x = frame % asset['columns'] * asset['cell_w']
        y = frame // asset['columns'] * asset['cell_h']
        frames.append(image.crop((x, y, x + asset['cell_w'], y + asset['cell_h'])).tobytes())
    assert len(set(frames)) >= 4, aid
    checks += 1
print(f'PASS: {len(candidates)} revision-2 character sheets, {checks} structural checks.')
