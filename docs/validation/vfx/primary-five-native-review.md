# Primary five VFX: development rendering review

2026-10-10. This approves these five raster records for development runtime rendering. It is not a finished-game quality, Android performance, balance, or final release approval.

## Exact reviewed source

Candidate JSON SHA256: afa9a294ae97e3a54741f49569682770f4f3b0afbe5baa7736852b1e109d8eec. The original candidate JSON and its `vfx_approved:false` flags remain unchanged. The five records are crescent slash, double-ring spin, cannon shell, contact blast and dust ring. Their PNG hashes remain exactly those in that candidate.

## Actual observation

Own cloud Godot 4.6.3 Compatibility renderer, native 800×450 window. `tools/qa/skill_vfx_native.tscn` used the real streamed-city Core, buildings, three ordinary brutes, actual attack/projectile/collision events, and the production WorldView. The scene explicitly replenished HP and used no SaveStore or user saves. Candidate-only metadata was labelled on screen.

- First run: actual 20 seconds/1,200 active ticks, 50 executed attacks and 7 projectile impacts in the captured trace. Crescent contact and the separate round spin shape were visible at their actual executed ticks.
- Second run: actual rightward input changed position and crossed origin chunk `[0,0]`→`[1,0]`. No render diagnostic appeared. This is real native movement evidence, separate from the earlier stationary run.
- Cannon attack at tick1201 produced an in-flight shell; actual collision at tick1208 replaced it with contact blast/dust at the Core impact position. No projectile animation started after impact.
- The paused contact comparison is tick1210. Changing the effect-reduction setting at this same active tick preserved the contact blast and omitted the optional dust. Presentation continued drawing without advancing combat time.
- Logical portrait450×800 and landscape800×450 layouts were directly viewed. The host window stayed800×450, so this verifies engine layout/aspect changes only, not physical Android rotation.
- Ground hazard remained distinguishable and visible with the new contact overlay. The player can still be obscured by overlapping giant bodies; this is an open readability issue, not resolved by this batch.

## Boundaries and remaining work

The first three base skills now have visually distinct primary effects. This does not complete all skill/evolution effects. Dust and blast polish, larger battle readability and smartphone performance still need real gameplay assessment. Native checkpoint restore is not claimed by these images; automated bridge restore/reset/rebase tests cover the corresponding state boundary. Independent code review identified duplicated actor-pose replay and its correction is verified separately before final integration.

The original five rejected character-art records and `final_export_allowed:false` remain protected. Raw approved VFX PNGs must be included by the export filter because runtime verifies their original bytes; no APK export is claimed here.
