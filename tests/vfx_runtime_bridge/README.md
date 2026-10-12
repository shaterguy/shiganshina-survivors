# Successful-tick runtime VFX bridge

The bridge is presentation-owned and never mutates Core, events, snapshots,
world/save authority, rewards or asset approval.

## Runtime API

- `WorldView.consume_combat_events(events: Array[Dictionary], current_snapshot: Dictionary) -> void`: call for each successful Core tick, before `consume_events(events)`. The snapshot must be from that same successful tick.
- `WorldView.consume_events(events: Array[Dictionary]) -> void`: legacy hit/death feedback. Real runtime player attack poses use executed `player_attack`; damage supplies hit feedback only.
- `WorldView.combat_vfx_commands(snapshot: Dictionary = {}) -> Array[Dictionary]`: active-tick commands and explicit diagnostics. With no argument, a newer successful-tick snapshot takes precedence over the previous rendered frame.
- `CombatVfxBridge.validate_batch(events: Array[Dictionary], current_snapshot: Dictionary) -> bool`: checks same-tick/run/sequence correspondence before WorldView changes any accepted scene observations.
- `CombatVfxBridge.consume(events: Array[Dictionary], current_snapshot: Dictionary) -> bool`: false refuses the entire stale/mismatched batch without advancing its event watermark.
- `CombatVfxBridge.present(snapshot: Dictionary, reduce_effects := false, visible_rect := Rect2()) -> Array[Dictionary]`: reconstructs only live Core reservations/projectiles; ephemeral casts require actual executed events. Frames/lifetimes use active ticks.
- `CombatVfxBridge.reset() -> void`: clears presentation observations. Present a restored snapshot to establish its historical event-sequence floor.
- `CombatVfxBridge.set_asset_metadata(metadata: Dictionary) -> void`: copies metadata and invalidates asset-byte checks. It never changes approval flags.
- `CombatVfxBridge.debug_stats() -> Dictionary`: event watermark, pool counts, origin revision/rebase count and explicit lifecycle diagnostics.

The `WorldView._combat_bridge` field permits the separately labelled QA scene to
use its candidate-review subclass. Production has no candidate approval bypass.
Production drawable commands require per-ID approved structural metadata,
matching source PNG SHA256 and decoded dimensions. Diagnostics never suppress
fallback sprites. Accepted VFX PNG source bytes must be preserved explicitly by
any later export-packaging work; native validation is not APK validation.

## Focused validation

`bash tools/test.sh vfx_runtime_bridge presentation_vfx city_presentation ui input app_vfx_dispatch`

The tests use real Core events, temporary authored-dimension test PNGs, actual
WorldView traversal and the renderer command builder. Only final GPU emission is
captured in ordering tests. They cover same-tick snapshot checks, event replay,
miss casts, damage separation, pause, restore/reset/new runs, origin translation
before ingest, registration of a later accepted subset, missing/unapproved/hash
failures, projectile contact retirement, reduced effects, city/finite depth-pass
order, landscape/portrait, exact fallback identity, gait rebase independence, stale-wrapper scene retention, player-pose replay floors, and rollback between rendered catch-up frames.
