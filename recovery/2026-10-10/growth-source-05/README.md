# NEW growth source preservation: tranche 05

This is a NEW implementation snapshot for 진격의 거인: 인류의 날개, chapter 시간시나구 탈출.
It is not recovery of the lost latest originals, a full game distribution, or an
Android-ready build. Source bytes were copied from the final accepted progression
inventory without alteration. This preservation step performed no upload, remote
Git operation, deployment or runtime activation.

## Contents and identity

The eleven NEW implementation files are four progression modules, evolutions.json
and six progression test scripts. The sixth test script is the final boundary
regression added before acceptance. Two independently written final regression
probes are also preserved byte-exact. All are inert .gd.txt or .json.txt snapshots.
A NEW minimal project.godot.txt is test support, not the game's configuration.
README, SOURCE-MANIFEST, TEST-RESULTS and PROVENANCE are newly authored or derived
product documents. They are not exact copies of original documents. No source
report or original document was changed.

SOURCE-MANIFEST.json records every snapshot's bytes, SHA-256 and Git blob SHA-1,
origin, mapping and transformation. Exact refers to the accepted current NEW
bytes; it does not establish historical latest-source recovery. The two retained
baseline data files and three test-harness dependencies are declared by exact
Git or prior-preservation identity, rather than duplicated in this tranche.

## Public progression interfaces and rules

- UpgradeCatalog owns candidates, option validation, stat/weapon_stats,
  xp_to_next and decoration. Catalog properties return deep copies. Invalid
  catalogs expose no rows; invalid stats fail closed to a finite neutral base.
  rebase_options rejects stale levels instead of silently repairing them.
- EvolutionCatalog provides validate, sorted ids, private definition copies and
  evaluate(state,id). Unknown/expired/invalid inputs return an empty result.
  It holds only a weak reference to the parent catalog. Recipes use the fixed
  chapter_01_shiganshina year 845 and the allowed equipment list.
- GrowthOfferService.materialize returns {ok,offer,next_rng_state} without
  changing its inputs. Only canonical run-bound issued descriptors are accepted.
  Ready evolutions sort first. Even level-source offers can receive one target
  priority card; other sorted legal candidates are sampled without replacement.
  Forced cards consume no selection/shuffle draws. Zero, one or two legal cards
  remain zero, one or two. A repeat pure call is intentionally deterministic.
- ProgressionView.build returns view_revision, slots, target, evolutions and
  active_offer. It preserves source identity, focus and stored levels, adds
  display fields, and disables stale cards. It never commits a choice, spends a
  seal or consumes RNG. Unsafe Object/nonfinite/cyclic source fragments fail
  closed; safe unknown metadata is omitted. Limits apply only to owned fragments,
  so unrelated large combat arrays are not rejected by catalog limits.

Damage and linear range modifiers apply once. Cooldown is rounded and clamped
to at least one tick. Range scales range/width/splash radius and evolved linear
geometry, not arc angle, hit count, stage delays or projectile speed. Evolution
preview effect values include current passive modifiers; recipe effect_params
retain unmodified tuning values. Actual combat snapshot integration is outside
this tranche and has not been verified by these tests.

## Verification and replay

Fresh isolated preservation runs reproduce focused progression 326 checks,
hostile-boundary probes 54 checks, and valid-state/lifetime probes 1,408 checks,
each with zero failures, exit 0 and no script/error/warning/leak diagnostics.
The latter samples 64 legal states and 128 owner/evolution release cycles.
These counts are separate bounded checks and are not a full-game passing total.
The existing broader progression-plus-contracts result remains recorded as not
green because missing dependencies and imported resources caused runtime errors.

To reproduce, use a separate empty test workspace. Restore only mapped snapshots
by removing their final .txt suffix. Materialize all five pinned dependencies
listed in SOURCE-MANIFEST.json and check their hashes first. Use Godot
4.6.3.stable.official.7d41c59c4 with writable isolated XDG data/cache/config folders.
From that workspace run:

    godot --headless --path . --script tests/run_all.gd -- progression
    godot --headless --path . --script tests/progression/independent-boundaries.gd
    godot --headless --path . --script tests/progression/independent-valid-states.gd

Require the exact expected result marker and count, zero failures, exit 0 and
absence of script/error/warning/leak diagnostics. The exact fixture helper from
the previous tranche supplies only stored test data here. Its shape-only helper
methods are not production validators. The small progression state fixture is
not a valid full Core save.

Actual Core source is not included, loaded or verified. Durable selection,
seal-ledger equality, queue activation, stale UI transaction rejection, healing,
attack execution, migration, restore, streamed world, full-suite integration,
Android gameplay/performance, balance, art and APK gates remain outside this
preservation and its bounded approval.
