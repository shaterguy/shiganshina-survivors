# Remaining skill rasters: development integration

Five original rasters are registered through the existing strict development-only
policy: dash compressed gas, dash cross tip, reentry triple, ally gas swoop, and
ally arrival cut. All three visual-review flags remain false. The five earlier
reviewed VFX, ten earlier development-only VFX, three dedicated enemy assets,
five rejected character blocks, and final-export denial are unchanged.

## Actual event and draw behavior

- Dash retains the real attack line origin, direction, length and width. Its tip
  is at the exact endpoint. No player displacement is introduced.
- Ally gas follows the actual projectile. The arrival uses the actual impact
  position and retains the existing 8-pixel zero-splash contact footprint.
- Reentry's Core event describes a player-centered acquisition circle and one
  target ID. It is not a 160-pixel area hit. A successful damage receipt with the
  same attack and target now supplies the frozen presentation contact position.
  The original Core geometry remains available as contact_geometry; the recipe's
  presentation_size_px=[36,36] is display-only. One triple shows all three blade
  axes together. Misses and armor_blocked do not produce a successful triple.
- A killed target may already be absent from the successful snapshot. Its actual
  damage.position remains the contact throughout ten visual ticks and coordinate
  rebases. A cold snapshot does not replay an old contact.
- Missing wire_anchor still omits the wire. No wire raster was added. The catalog
  continues to report only missing_art:vfx_wire_taut for the full recipe set.

## Reproduction and review boundary

The untouched source images, generation provenance, packing settings, original
candidate descriptor and review notes are retained. VISUAL_REVIEW.md and
focused-verification.json describe the original isolated art handoff; this file
records the later runtime registration. The original candidate descriptor remains
unapproved and has no development activation fields. Only the live manifest adds
those fields.

Run: python3 tools/art/vfx_remaining/verify_remaining.py
This reproduces all five atlases and forty frames byte-identically. Original
checksums in docs/art/vfx/file-checksums.json also remain valid.

The headless tests use real Core events, the registered manifest, the public
WorldView traversal and its actual texture-region draw adapter. They compare
emitted ImageTexture cell bytes, pivots, directions, transforms, contact positions,
expiry, replay, miss, armor block, killing hits and reduced-effect behavior.
They do not establish native playback readability or visual approval.

Focused runtime: bash tools/test.sh remaining_vfx development_vfx presentation_vfx vfx_runtime_bridge app_vfx_dispatch build assets enemy_art_integration
Packaging: python3 -m unittest discover -s tests/build -p 'test_*vfx_packaging.py'
Protected manifest: python3 -m unittest discover -s tests/assets -p test_recovered_armored_v6.py
Enemy packaging: python3 -m unittest discover -s tests/build -p test_enemy_art_packaging.py

The observed three-skill scenario peaks at six commands: four mandatory skill
layers plus two separately timed hit sparks. The five added originals and the
existing spark each validate once per immutable Bridge configuration; 160
unchanged presents cause no further original-byte validation. This is bounded
command/cache verification, not a device frame-time benchmark.

No Core, damage calculation, save schema, gameplay definition, native input,
APK, external release or final-art approval is changed by this integration.

## Confirmed-contact size validation

The reentry cast phase requires exactly two numeric, finite, positive display axes
that remain finite and positive as Canvas Vector2 components. Missing, malformed,
zero, negative, nonfinite, overflowing or underflowing values are rejected by
Catalog.validate. Renderer independently emits invalid_presentation_size and no
raster command if a malformed effect reaches it. This is limited to the new
confirmed-contact display-size contract; general event validation is unchanged.

Focused contract regression: bash tools/test.sh remaining_vfx_contract
The actual Core hit is reused for all mutations; the valid 36x36 output and the
independent hit spark stay unchanged.
