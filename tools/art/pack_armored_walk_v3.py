"""Pack independently drawn alternating gait poses; never synthesize gait by moving pixels."""
from pathlib import Path
import json
import os
import re
import shutil
import sys
import tempfile
import pack_atlases as art

ROOT = Path(__file__).resolve().parents[2]
REVISION = sys.argv[1] if len(sys.argv) > 1 else 'v3'
MAP = ROOT / ('docs/art/armored-walk-source-map.json' if REVISION == 'v3' else f'docs/art/armored-walk-{REVISION}-source-map.json')
SOURCES = json.loads(MAP.read_text())
FRAMES = ROOT / f'assets/art/characters/armored_titan_{REVISION}_frames'
FRAMES.mkdir(exist_ok=True)
WALK = ROOT / f'assets/art/source/armored-walk-{REVISION}'
WALK.mkdir(exist_ok=True)
# Contact/down/passing/up repeat with the opposite leg. The art changes the joint
# poses; these small registration heights preserve the deliberately drawn weight shift.
HEIGHTS = [236, 232, 240, 244, 236, 232, 240, 244]

for frame in range(12):
    shutil.copyfile(ROOT / f'assets/art/characters/armored_titan_v2_frames/{frame:02}.png',
                    FRAMES / f'{frame:02}.png')

with tempfile.TemporaryDirectory(prefix='shiganshina-gait-') as temp:
    t = Path(temp)
    os.environ['XDG_CACHE_HOME'] = str(t / 'cache')
    for i, source in enumerate(SOURCES):
        source = Path(source)
        if not source.is_absolute():
            source = ROOT / source
        target_source = WALK / f'phase-{i:02}.png'
        if source.resolve() != target_source.resolve():
            shutil.copyfile(source, target_source)
        raw, alpha, clean = t/'raw.png', t/'alpha.png', t/'clean.png'
        art.run(target_source, '-channel', 'A', '-threshold', '55%', '+channel', raw)
        art.run(raw, '-alpha', 'extract', alpha)
        report = art.run(alpha, '-define', 'connected-components:verbose=true', '-connected-components', '8', 'null:')
        component = re.search(r'^\s*(\d+):.*(?:gray\(255\)|srgb\(255,255,255\))', report, re.M)
        assert component, i
        art.run(alpha, '-define', 'connected-components:mean-color=true', '-define',
                'connected-components:keep='+component[1], '-connected-components', '8', clean)
        art.run(raw, '-alpha', 'off', clean, '-alpha', 'off', '-compose', 'CopyOpacity', '-composite',
                '-compose', 'Over', '-trim', '+repage', '-filter', 'point', '-resize', f'x{HEIGHTS[i]}',
                '-background', 'none', '-gravity', 'south', '-extent', '192x256', raw)
        art.run(raw, '-alpha', 'extract', alpha)
        art.run(raw, '-alpha', 'off', '-dither', 'None', '-remap', art.PALETTE,
                alpha, '-alpha', 'off', '-compose', 'CopyOpacity', '-composite',
                '-define', 'png:color-type=6', FRAMES/f'{12+i:02}.png')

art.run('montage', *sorted(FRAMES.glob('*.png')), '-tile', '4x5', '-geometry', '192x256+0+0',
        '-background', 'none', '-define', 'png:color-type=6',
        ROOT/f'assets/art/characters/armored_titan_{REVISION}.png')
previews = ROOT/'assets/art/previews'
art.run('montage', *[FRAMES/f'{12+i:02}.png' for i in range(8)], '-tile', '4x2',
        '-geometry', '192x256+12+16', '-background', '#293136',
        previews/f'Shiganshina-armored-walk-{REVISION}-cycle.png')
art.run('-delay', '14', *[FRAMES/f'{12+i:02}.png' for i in range(8)], '-background', '#293136',
        '-alpha', 'remove', '-loop', '0', previews/f'Shiganshina-armored-walk-{REVISION}.gif')
print(f'Prepared {REVISION} atlas, eight-phase cycle PNG and movement GIF; manifest unchanged.')
