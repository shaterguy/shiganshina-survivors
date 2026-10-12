"""Structural/timing checks only. The candidate still requires real-play visual review."""
from pathlib import Path
from PIL import Image
import json
import sys
import hashlib

ROOT = Path(__file__).resolve().parents[2]
revision = sys.argv[1] if len(sys.argv) > 1 else 'v3c'
atlas_path = ROOT/f'assets/art/characters/armored_titan_{revision}.png'
candidate = Image.open(atlas_path)
palette = {tuple(bytes.fromhex(c[1:])) for c in json.loads((ROOT/'assets/manifest.json').read_text())['palette']}
assert candidate.mode == 'RGBA' and candidate.size == (768, 1280)
assert {p[:3] for p in candidate.get_flattened_data() if p[3]} <= palette
assert {p[3] for p in candidate.get_flattened_data()} <= {0, 255}
frames = []
for i in range(20):
    frame = candidate.crop((i % 4 * 192, i // 4 * 256, (i % 4 + 1) * 192, (i // 4 + 1) * 256))
    assert frame.getchannel('A').getbbox(), i
    assert len({p[:3] for p in frame.get_flattened_data() if p[3]}) >= 8, i
    frames.append(frame)
    if i < 12:
        old = Image.open(ROOT/f'assets/art/characters/armored_titan_v2_frames/{i:02}.png').convert('RGBA')
        assert old.getchannel('A').tobytes() == frame.getchannel('A').tobytes(), i
        assert all(a[:3] == b[:3] for a, b in zip(old.get_flattened_data(), frame.get_flattened_data()) if a[3]), i
assert len({f.tobytes() for f in frames[12:]}) == 8
gif = Image.open(ROOT/f'assets/art/previews/Shiganshina-armored-walk-{revision}.gif')
assert gif.n_frames == 8 and gif.info['loop'] == 0
durations = []
for i in range(gif.n_frames):
    gif.seek(i)
    durations.append(gif.info['duration'])
assert durations == [140] * 8 and sum(durations) == 1120
print(f'PASS: {revision} RGBA/palette/20 frames/12 preserved visible frames/8 unique poses/1120ms loop. Gait quality remains a separate visual gate.')

if revision == 'v3c':
    annotations = json.loads((ROOT/'docs/art/armored-v3c-limb-landmarks.json').read_text())
    assert annotations['atlas_sha256'] == hashlib.sha256(atlas_path.read_bytes()).hexdigest()
    for i, f in enumerate(annotations['frames']):
        right_arm = f['RA'][-1][0] - f['RA'][0][0]
        right_leg = f['RL'][-1][0] - f['RL'][0][0]
        left_arm = f['LA'][-1][0] - f['LA'][0][0]
        left_leg = f['LL'][-1][0] - f['LL'][0][0]
        assert right_arm * right_leg < 0, i
        assert left_arm * left_leg <= 0, i
    print('PASS: all eight hand-inspected phase annotations oppose same-side arm/leg travel; not an automatic visual-quality claim.')
