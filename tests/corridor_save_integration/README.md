# Corridor save integration

Independent regressions for the dev8 corridor change. Production app, contracts,
and persistence files are not modified by this suite.

## Run

From the project root, with Godot 4.6.3:

```sh
flock /tmp/wings-dev8-godot.lock env \
  SHIGAN_TEST_DATA_HOME=/tmp/wings-dev8-save-tests/data \
  SHIGAN_TEST_CACHE_HOME=/tmp/wings-dev8-save-tests/cache \
  SHIGAN_TEST_CONFIG_HOME=/tmp/wings-dev8-save-tests/config \
  bash tools/test.sh corridor_save_integration
```

Each scenario uses a new isolated `user://corridor_save_.../saves` path. The
fixture writer deliberately writes original v1 JSON (with whitespace) directly;
using today's `commit_game` to manufacture old bytes would hide normalization
bugs. Subsequent reads, preparation, confirmation, controller resume and saves
all use the actual product implementation and real world-page disk store.

## Captured baseline

The genuine legacy source is `v0.1.0-dev7`, commit
`38b0cb1e70ef7c04a952568597a3ffc983d91945`.
`fixtures/provenance.json` records the checked 19-file final dev7 delta manifest,
relevant baseline source hashes, generator hashes and every captured fixture
hash. The provenance test checks fixture and generator integrity.

The baseline was a separate source copy, updated only with the four final dev7
version files before capture. All 19 final-manifest entries matched. Capture used
an independent XDG profile. No candidate product source generated these legacy
states, and no actual user save was opened or modified.

`generate_legacy_city.gd` must run with that unchanged baseline as `--path` and
this generator's absolute path as `--script`. Set `CORRIDOR_FIXTURE_OUTPUT` to a
writable output directory. It uses the original controller fixture to arrange a
safe ground approach, then normal input/Core ticks produce all five phases.
Each packet contains an actual stored GameSave envelope from the shipped City
provider. `generate_legacy_interior.gd` adds two real `over` ticks before capture.
It also captures the existing authored one-roof test-provider interior state for
Core-level tests. Capture scripts are retained as non-test, source-controlled
reproducibility helpers and are never run by `tests/run_all.gd`.

The tests add explicit nonzero preservation sentinels after capture: profile
credits 431, kills 3, damage 37.5 and one prior mobility hit ID. These are valid
test data, not claims that the values were naturally earned. Both unchanged dev7
and the dev8 candidate admit those envelopes before the migration assertions.

## Coverage

- All five legacy phases from both authored and shipped-city geometry pass the
  actual GameSaveStore → GameSaveContracts → PreparedCityRuntime preparation and
  confirmation path without writing on read or changing the source byte hash.
- Normalization is pure and idempotent; prepared state equals canonical saved
  state. Same-revision changed economy is refused as an authority mismatch.
- Structural and geometry-corrupt v1 data are rejected before migration.
- Already-clear current positions are retained. A genuine full-city roof-interior
  save has blocked ordinary ground clearance and returns to its stored start.
- Real cold Controller Continue, cleared input, default asynchronous save,
  second startup and following gameplay tick never resume old roof movement.
- A failed first migrated write retains the exact v1 file; retry publishes v2
  once. An uncertain post-replace result reconciles the exact v2 commit without
  another revision or live-state rewind. The first successful write preserves
  exact v1 bytes as its backup.
- Coins, every unrelated state field, statistics, both RNG streams, timers,
  cooldown, cast identifiers and prior hit IDs are preserved.
- Actual v2 paired-anchor boost survives disk and prepared-state roundtrips;
  cleared resume input stops it at the next tick. Ordinary shipped-city default
  asynchronous saves remain valid.

The migration's third-choice landing fallback is a defensive branch, not an
observed full-restore scenario. Full legacy validation verifies the complete rise
sweep from the start and the final landing before migration. A fabricated blocked
start is not allowed to bypass that validation. Current-position and start-point
choices have genuine saved-state integration evidence; landing fallback is not
claimed as covered by an authentic save.

## Scope

Keep this directory's `.gd`, `.gd.uid`, JSON fixtures, provenance and README in
source. Transient Godot caches, isolated profile data and capture/test logs stay
outside source. Headless tests establish host-side save behavior, not Android
installation, device performance or frame-rendering quality.
