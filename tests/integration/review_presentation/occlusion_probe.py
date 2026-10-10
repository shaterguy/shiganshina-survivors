"""Read-only alpha intersection for the reviewed player's/Armored's draw calls."""
import json
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[3]
assets = json.loads((root / "assets/manifest.json").read_text())["assets"]
armored = Image.open(root / assets["armored_titan"]["path"].removeprefix("res://"))
player = Image.open(root / assets["garrison_01"]["path"].removeprefix("res://"))
covered = total = 0
# World probe: clock=10; Armored move frame 1 at (0,100), scale 1.5;
# player idle frame 0 at (0,0). Both sprites use their actual manifest anchors.
for y in range(64):
    for x in range(64):
        if player.getpixel((x, y))[3] < 128:
            continue
        total += 1
        ax = int(192 + 96 + (x - 32) / 1.5)
        ay = int(256 + (y - 64 - 100) / 1.5)
        covered += armored.getpixel((ax, ay))[3] >= 128
print(f"ARMORED_OPACITY covered={covered} player_opaque={total} ratio={covered / max(total, 1):.6f}")
