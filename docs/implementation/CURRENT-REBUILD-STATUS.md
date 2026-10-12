# Current development status — Source21, 2026-10-11

This incomplete development snapshot extends Source20. Historical rebuild reports remain evidence of their stated dates; this file supersedes their current-stage descriptions. It is not a signed APK, final art acceptance, or Git publication record.

## Connected product path

- The actual project main scene now configures the streamed city runtime before the existing Controller enters the tree. A normal new departure uses the city. Configuration failure is visible and does not silently fall back to the finite test world.
- The canonical save path remains `user://saves`. Existing dev1 settings, progress and career migration remain guarded. A fully validated current finite checkpoint uses the existing explicit preserve-and-start-new-run flow; malformed or future data is not promoted to a compatible save. City checkpoint validation, Store, Controller and Core are unchanged.
- Existing combat, evolution, supply purchases, asynchronous autosave, city collision/destruction, final actor, dock handoff, 75-second deadline, physical exit and settlement are connected. Six-role admission/attack models remain unadopted: the current runtime still uses its earlier enemy behavior implementation.
- Content revision remains `ch01.3-rebuild.2`. Source20's Korean font/theme, read-only locked-shop focus, manifest and all art remain unchanged. New articulated Armored charge/contact work is still an isolated rendering candidate.

## Verified boundaries

- Final isolated candidate GDScript suite: 80,838 checks, zero failures. Focused startup/recovery/controller suite: 513/0. The six integrated source/test files match that reviewed candidate byte-for-byte; a separate post-integration bootstrap run passed 135/0.
- A newly executed actual-main fixture passed 64/0 and a second OS process cold test passed 13/0. Real departure, movement, final actor and warning, city-to-dock save acknowledgement, physical exit, one 70-credit settlement, cold reload and new serial were exercised through existing product APIs.
- That fixture arranged tick 107,999 and position once after a real initial tick, then refilled HP 4,556 times; real damage occurred on 23 ticks. It exercised 4,500 deadline ticks plus 128 physical-exit ticks. It is not natural 30-minute survival or a rendered playthrough.

## Still required

- Native three-minute play and actual frame-time/readability acceptance, followed by natural endurance and balance. Headless pass counts and prior host font measurements do not establish Android performance.
- One live Armored renderer with arbitrary contact-phase handoff, actual wall contact, recovery, directional limits and pixel/depth verification. Separate animation clips are not product integration.
- Actual diverse enemy attacks and five distinctive intermediate bosses, complete skill-effect coverage, consistent action art and replacement audio. Five original canon asset blocks and `final_export_allowed=false` remain.
- Android in-place update, touch/lifecycle and physical gamepad checks. No new installation or release is represented by Source21.

Source21's archive provenance identifies the exact changes and test evidence. Prior reports are retained as historical evidence and are not re-labelled as tests of this snapshot.
