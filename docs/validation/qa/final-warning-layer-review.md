# Final threat warning visibility

2026-10-10 09:03 UTC. Native Godot 4.6.3 Compatibility renderer, actual WorldView and game UI, 800×450 and 450×800 SubViewports.

The developer-only `final_threat_viewer.tscn` explicitly fast-forwards a fresh fixture to survival tick107999, then uses the real director/simulation to enter evacuation and generate its first warning at active tick108150. It is a rendering fixture, not evidence of a continuous30-minute human playthrough or Android OS rotation.

The original rendering order put hazards under all opaque enemy sprites. With the player overlapping the large Armored Titan, most of the attack warning was hidden. The regression `tests/ui/test_warning_layer_order.gd` observed the real draw traversal:120 UI checks with2 expected failures before the fix.

The minimal fix draws each hazard once after enemies/projectiles and before the player. Collision geometry, timing, damage, raster footprints and opacity are unchanged. Independent review passed. Fresh full Godot run:75,505 checks,0 failures. Native landscape and portrait rechecks show the full circular border/hatching over the giant while the soldier remains visible on top.

Actual screenshot captures:
- Before: `dist/screenshots/game-1791622807.png` (portrait, tick108150)
- After: `dist/screenshots/game-1791622949.png` (landscape, tick108150)
- After: `dist/screenshots/game-1791622983.png` (portrait, tick108150)

These captures use the current approved-canon v2 nonwalking Armored pose; v5 packing preserves that exact idle cell. The large giant extends above the landscape camera at this position, while the portrait viewport shows its full body. The player, warning, evacuation instruction, timer, dock direction and controls remain readable. Delivered DEV1 is unchanged; the correction belongs to a later build.
