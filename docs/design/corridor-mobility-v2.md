# Corridor mobility v2

This replaces live roof-vault movement in the dev8 development build. It does not change chapter content fingerprints or add new scenery.

## Runtime

Core alone owns activation, movement and path damage. Presentation reads Core state and cannot move the player. A valid proposal selects two intact anchors on opposite sides of the player's input heading, using the prepared spatial prop index. Buildings and future authored tree-anchor records use the same catalog contract.

The cast has a straight ground-plane path. Every segment uses the ordinary radius-8 player sweep; no roof-pass exemption is used. Speed is 480 px/s (8 px per fixed 60 Hz tick), range is at most 320 px, cooldown is 120 ticks from activation, and path damage is 12 with width 20. Each enemy can be hit at most once per cast. Both anchors are checked before movement and again before damage.

The seed/tick/cast hash screens activation without consuming simulation RNG. The existing eligible-tick chance is retained. Heading remains fixed during the cast. Input release or opposing input ends the cast at the current safe ground position; small joystick deviations do not cancel. A broken anchor or newly blocked sweep ends safely.

## Saved state

Mobility schema v2 has `ground` and `boost` phases, an `anchors` pair and two absolute ground-plane path points. Geometry fingerprints, exact field sets, cast timing, direction, progress, anchor sides and player position are validated. A grounded state retains the last cast identity, cooldown, roll and hit history until the next cast.

Legacy v1 snapshots are accepted only through their original structural and geometric validation. They are then converted to v2 ground state before publication; old roof flight is never resumed. City migration prefers the current walkable point, then the saved start, then the saved endpoint. Existing dock-ground snapshots use the dock's ordinary walkability rules. Velocity is cleared; unrelated run state, statistics, currency, clocks and RNG remain unchanged. No safe point means an explicit failure, without modifying the source save. Normal atomic persistence writes the migrated state; reading alone does not replace old saved bytes.

## Presentation

Two wires attach to the side anchors. The player retains ordinary ground depth and interpolation. A cyan directional trail distinguishes the movement from red enemy warnings. There is no roof arc, roof-depth override or landing ring. Audio uses launch/gas and wire release without a heavy roof-landing sound.

## Verification limits

Headless Core/save/command tests and Linux X11 raster captures are distinct evidence. Neither establishes Android GPU performance, touch behavior or long-duration device stability. The development-only art gate remains unchanged.
