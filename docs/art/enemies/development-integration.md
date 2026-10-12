# Distinct ordinary enemy development integration

Development candidate based on committed `93498a9817397b821a4a6e745383332047837b98`.
Only three new runtime IDs are registered. No combat, collision, damage, world,
Director, walking-frame count, or existing character records are changed.
The original five rejected-character blocks and `final_export_allowed=false`
remain unchanged. This is not native Android or gameplay visual approval.

## Selected original raster inputs

All pixels originate from the supplied built-in image-generation source bundle.
The original three generations, two targeted second-walk edits, exact prompts,
source crop/ground-anchor records and checksums are preserved separately in the
reviewed art bundle. There are no anime-frame extractions or procedural bodies.
`pack_enemy_diversity.py` consumes the supplied atlases without modifying them.
It preserves exactly the original alpha>=128 pixel mask and maps solid RGB to
the shared palette by squared sRGB distance, without dithering or added pixels.

- Quadruped: input `b6833aeb3ba0e51dc0b1a87f590a06e085ddc6b18e3d5cd8dbfd14fac347a384`; output `179a1207400b53551af67358c378324763a13ac5d70265e10692654aefe32272`
- Thrower: input `09dae345f7ed744bb3409eb789e86fd4551736649f038a2435b8d37702478fe2`; output `c701e2e5bf4263a736babed63c5777bf3b9b6ced957229130ffe6f684abf7ab8`
- Stone: input `35e352ef7bb5fde1039e3ceeeccd93ab3ef7e422e4c85a277638ac44851f0813`; output `24e4a2e7fd3326c4f46a267c9e5741e03e4c36310e86b07394c047b4c2465fcc`

The thrower alone excludes darkest palette entry `#20252c` from nearest-color
selection. The original, unrestricted 24-color, and constrained 23-color packs
were compared once at scale 1 against actual lightest/darkest city-tile cells
with the production tint. The constrained pack modestly improves dark rear-leg
and shoulder continuity while retaining the dark shoulder mass and gray stone.
It changes 13,384 solid RGB pixels from `#20252c` to `#30343b`; masks and anatomy
are unchanged. Dark shading is flatter/lighter, and scene contrast remains a
native gameplay review concern. Quadruped and projectile map against the full shared 24-color palette and
use 17 and 10 colors respectively. The thrower maps against 23 destinations
and uses 18 colors.

## Exact rendering contract

- Quadruped: five 144x96 cells in a 720x96 row, ground anchor [64,88]
- Thrower: five 192x176 cells in a 960x176 row, ground anchor [72,168]
- Stone: one centered 16x16 cell, anchor [8,8], drawn at authoritative radius 7
- Frames 0/1: exactly two walking poses at 6fps; no generated in-between poses
- Frame 2: warning windup; frame 3: body contact or empty-hand rock release
- Frame 4: recovery, also reused for idle/hit/death

There is no bespoke hit or death pose. A standing/recovering still remains the
short corpse image, and hit feedback uses the same still plus existing feedback.
WorldView currently maps harmless recovery to idle, which selects this same cell.
These limitations are deliberate for the minimal ordinary-enemy set and are not
an assertion that reaction/death animation quality is complete.

Facing-right atlases mirror around their constant ground anchor. Actual body
radii remain 18/24, and attacks remain exclusively Core geometry. Forward reach
in asymmetric sprite cells does not grant attack range. Release/recovery contain
no held stone. The separate stone is drawn at `projectile_pose.current` only
while Core says visible, and expires without ghost pixels at a blocking wall.

New `.import` files use lossless compression, no mipmaps, and disabled alpha-border
RGB rewriting. The existing nearest texture filter is retained. Headless tests
compare actual loaded resource cell bytes, draw transforms, mirrored bounds,
and corresponding Core state without loosening pixel assertions.

## Packaging and scope

Only the three exact runtime PNG paths are added to Python/Godot path predicates.
They require the exact sprite/projectile kind, selected packing profile,
`enemy_art_development_ready=true`, and their own `export_blocked=false`.
Source, preview, alternate frame and arbitrary nested paths remain excluded.
The final export gate is still denied. No export-filter wildcard was introduced.
`development-runtime-candidate.json` locks the additive records; the existing
Armor-only baseline test removes only exact matching additions before checking
its unchanged original semantic fingerprint.

## Evidence limits

Real Core finite and prepared-city W/A/R states, movement, both facing directions,
projectile position/diameter, resource pixels, blocked-rock cleanup and package
predicates are checked headlessly. Only the raster-emission boundary is captured.
This does not test a GPU-composited gameplay frame, animation/contact feel,
Android display density, device performance, or a complete played run.

Native QA selection was denied twice in the surrounding work. No alternative
GUI, input, CLI native launch, or access route was used to bypass that denial.
No external upload, Git publication, APK build, or active-source edits are part
of this isolated candidate. Existing full-suite diagnostic failures are recorded
separately; focused green checks do not assert full-suite or native PASS.
