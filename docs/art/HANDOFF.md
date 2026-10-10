# Shiganshina runtime art handoff

## Current status: revision 2, final export blocked

- Seven character entries now point to inspected versioned PNGs: `garrison_01`, `titan_basic`, `titan_brute`, `titan_grabber`, `boss_sweeper`, `boss_grabber`, `armored_titan`.
- Five remain rejected and blocked: `titan_runner`, `titan_sweeper`, `boss_charger`, `boss_leaper`, `boss_abnormal`. Their entries have `export_blocked: true`, `reason: "canon_revision_pending"`, and `review_status: "rejected_incorrect_clothing"`. They must not appear as accepted final art or in a deliverable APK.
- Their requested nonsexual canonical revisions are unavailable. The rejected clothed designs remain unapproved.
- The integrator verified the export preflight on an actual Android export invocation: all five blocked IDs were reported, the process exited with code 3, and no APK was generated. The manifest also declares `art_revision_status.final_export_allowed: false`.
- Current manifest SHA-256: `cf3183c45f389ba00387c78ca0084924947a358d5e8ff1b5f1993e48318dde24`.
- Current 74 entries / 71 distinct runtime paths, 4,696,644 source bytes. The following previous-footprint section is historical.
- Preserved stable IDs, dimensions, anchors and animation state contracts. Version-2 provenance contains each replaced path and hash.
- Validation after atomic replacement: candidate checks 137/137; full raster/audio/geometry checks 41,600; Godot asset checks 852, zero failures. These structural checks do not override unresolved visual/canon status.
- Revised source and packed frame inspection confirmed continuous unclothed skin and omitted sexual characteristics in the five successfully revised ordinary/miniboss sheets. Garrison patch/blades/ODM and Armored Titan organic plates/joints/face were also corrected.
- See `canon-v2-review.md` for official references, exact blocked categories and user-delivery history. Prior source files/previews remain provenance only and are excluded by runtime whitelist.

## Previous structural deliverable

- 74 manifest records, 71 distinct runtime files: 56 PNGs and 15 WAVs.
- Runtime source-file footprint: 4,702,765 bytes, excluding source studies, previews, import caches and code.
- Manifest SHA-256: `f74665411efe1918250529f176b546a166abac64c2f2fdf4de9a3c6246eee055`.
- Game icon: `res://assets/art/ui/game_icon.png`, 512×512 opaque RGBA.
- Native authored sprite scale: garrison 64×64; five regular giant types 96×144 through 128×176; five minibosses 128×192 or 144×208; Armored Titan 192×256.
- Built-in image generation produced original character, prop, UI, illustration and battle-effect art. Runtime files were prepared with nearest-neighbor scaling, exact cells, hard alpha and shared 24-color remapping. The danger masks are original exact-geometry raster diagrams. Audio consists of original score/waveform synthesis, with no third-party music or samples.

## Integration contract

`assets/manifest.json` is authoritative. Top-level `assets` maps stable IDs to records. Paths are `res://` paths. Animations contain `frames`, `fps`, `loop`. Frame indices are zero-based row-major; use `columns`, `cell_w`, `cell_h` for crop rectangles. Do not assume uniform cell sizes across characters. All character anchors are bottom-center; icons use center anchors; tiles and panel textures use top-left anchors. Use nearest filtering and no mipmaps.

- Player: `garrison_01`; 2 idle, 6 move, 2 windup, 3 attack, 1 hit and 2 death frames.
- Regular enemies: `titan_basic`, `titan_runner`, `titan_brute`, `titan_sweeper`, `titan_grabber`.
- Minibosses: `boss_charger`, `boss_sweeper`, `boss_leaper`, `boss_grabber`, `boss_abnormal`.
- Final threat: `armored_titan`; has entry and retreat, no death animation. The runtime must not introduce a kill animation or kill objective.
- Ground: `city_tiles`, `canal_water`, `dock_planks`; each has 32×32 cells. Water has a four-frame idle animation.
- City: `house_narrow`, `house_warehouse`, `house_bakery`, `house_ruined`, `wall_segment`, `wall_breach`, `cannon_prop`, `refugee_wagon`, `burning_rubble`. Fire has four 96×96 frames.
- Opening illustration: `colossal_intro` 640×360.
- Nine-patches: `panel_default`, `panel_focus`, `panel_pressed`, `panel_disabled`, all 64×64 with 12-pixel margins.
- Virtual stick: `ui_stick_base` 96×96 anchor[48,48], `ui_stick_knob` 40×40 anchor[20,20]. Set translucency at runtime so controls do not obscure the world.
- Attack/effect: `slash_fx`, `impact_fx`, `gas_fx`, `debris_fx`; shared sheet with four sequential frames per effect, 64×64, anchor[32,32].
- UI IDs and equipment mappings are explicit in the manifest. `gamepad_a`, `gamepad_b`, `pause_icon`, `xp_pickup`, `danger_marker`, `escape_marker` are separate 32px files. The ally icon is composed from the actual original garrison sprite.

## Danger geometry

- Circle: 64×64, anchor[32,32], radius32; scale uniformly to gameplay radius.
- Sector: 128×256, anchor[0,128], right-facing 90-degree sector, radius128; scale uniformly and rotate to direction.
- Capsule/line: 128×32, anchor[16,16], centerline length96 and width32. Render with three horizontal slices: 16px left cap, 96px center, 16px right cap. Caps must be scaled uniformly to width/2; center must stretch to the gameplay centerline length. Nonuniformly stretching the whole image would make the end caps elliptical and is not valid.
- Every nontransparent warning pixel center lies inside the exact geometry. Borders and hatch lines remain inside that region.

## Audio

13 one-shots: `slash`, `hit`, `hurt`, `cannon`, `gas`, `step`, `xp`, `select`, `cancel`, `level_up`, `boss_spawn`, `victory`, `death`.
2 original 16-bar loops: `combat_loop` (112 BPM, about34.29s), `boss_loop` (132 BPM, about29.09s). All are mono 22,050Hz 16-bit PCM, peak below0.83. Looping is declared in manifest metadata; the Godot consumer must configure `AudioStreamWAV.LOOP_FORWARD` and the actual sample-count loop end. Synthesis/decoding/level integrity has been checked; final on-device mix and feel require the integration pass.

## Validation and remaining integration

- `python tools/art/validate_assets.py`: RGBA, palette, alpha, nonempty referenced frames, unique movement frames, SHA-256, WAV format/non-clipping, and exhaustive warning-mask geometry.
- `bash tools/test.sh assets`: Godot manifest/file/checksum/PNG/animation/anchor/WAV decoding suite.
- Sprite sheets and previews have been visually inspected. Actual in-game visual scale, audio mixing, frame-state transitions, touch layout and APK behavior remain the integration owner's verification scope.
- The basic and runner generated falling poses crossed source cell boundaries and were rejected. Their death animation uses inspected kneel/lying frames10 and11; unused frame9 is a duplicate, never an extra unique pose.
- Keep only manifest paths in APK runtime inclusion. Source generations, candidate studies, individual frame exports and previews remain available for editable source/provenance but are not runtime dependencies.
- Assets are fan-game material for the requested private prototype. Underlying Attack on Titan intellectual property remains with its rights holders; these are not official assets.

- 2026-10-10 07:06 UTC integration report: combined automated checks 2,545 with zero failures; blocked Android export stopped with exit 3 and no APK output. Actual v2 runtime visual review continues with integration.

## Locomotion review update

User-reported same-leading-leg motion exposed an additional visual defect in the previously accepted character previews. All seven successful character movement sets require locomotion review/correction independently of the clothing/canon gate. Armored Titan v3c is the latest eight-pose alternating-walk candidate with corrected opposite-arm phases; it is not yet the runtime manifest asset. All seven successful character movement sets remain subject to final locomotion review, and the other six have not yet been corrected. See walk-cycle-audit.md; do not treat prior frame uniqueness checks as gait approval.
