# UI/controller source preservation: tranche 03

This inert source archive preserves the twelve-file candidate inventory, the NEW
final UI, two NEW diffs, and a standalone isolated test reproducer. Nine candidate
files are stored here. Two unchanged tests are referenced from tranche 01 and one
unchanged fixture from tranche 02, with exact byte/hash verification recorded in
SOURCE-MANIFEST.json. The input router is intentionally present here even though
tranche 01 also contains it, so the isolated reproducer is self-contained.

Historical identity is asserted only where a recorded historical hash exists.
The controller matches the I2RR-1 stage; the router and final reassembled loadout
also match their recorded hashes. This does not establish later world-identity
controller changes. Complete captured source bodies without historical final
hashes remain explicitly unverified as to final historical identity. The candidate
UI is only partial historical recovery. Its missing old deferred-layout call site
has not been recovered. The focus and lifecycle changes here are newly authored.

All code/data/diff snapshots retain their original subpaths and add .txt. Nothing
is activated automatically. No production tree is overwritten. Raw recovery
reports are deliberately excluded. Test doubles and presentation DTOs live only
under test-fixture-evidence and are NEVER production assets or validators.

Reproduce in a new directory with an already installed Godot 4.6.3:

    python3 tools/replay_new_ui.py.txt
    python3 tools/reproduce_isolated_tests.py.txt --output /tmp/ui-tranche-03-check

The output path must not exist and must be outside this preserved directory.
The replay checks both NEW patches in memory without changing source files.
The runner copies only six UI/input modules and seven explicit test fixtures into
a new test-fixture-evidence workspace. It performs 79 presentation/input and 14
layout/lifecycle assertions, plus an independent free probe checked for engine
errors. TEST-RESULTS.json records a fresh preservation-time execution and input
hashes. These checks do not run the controller or supply-service integration.

No full game, missing Core/economy/catalog/migration/fixture recovery, Android
build, device acceptance, historical final-state proof, or remote publication is
claimed. Original dependency-blocked regressions are preserved, not passed.
