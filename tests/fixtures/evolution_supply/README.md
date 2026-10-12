# NEW R0 fixtures

These files were authored on 2026-10-10. They are not lost-original recovery and are not production-valid snapshots until R1/R2/R3 rebind them to actual validators.

- run_v2.json: one initial nonstreamed standard-doctrine reference
- game_save_v2.json: empty and started authorities
- progression_views.json + progression_source_offers.json: four rendering views and corresponding source-offer samples
- supply_views.json: four complete rendering examples, including genuine specified loadout options
- attack_events.json: blade immediate, wing-cut two-stage and crossfire locked-point examples; `{events,reservations}` per case
- content_identity_basis.json: explicit contract-only reference identity, not final production content fingerprint
- provenance.json: file/source hashes, transformation, case names and claim limits

The parent contract is docs/design/rebuild-contracts-v1.md. The helper at ../evolution_supply_fixture.gd is test-only. In particular, make_run and validate_checkpoint are SHAPE-ONLY FAKES; output must identify that use, and production must never import them.

Run only these contracts from the candidate root:

    XDG_DATA_HOME=/tmp/shiganshina-godot/data XDG_CACHE_HOME=/tmp/shiganshina-godot/cache XDG_CONFIG_HOME=/tmp/shiganshina-godot/config godot --headless --path . --script tests/fixtures/r0_contract_runner.gd

Also fail the check if output contains SCRIPT ERROR: or ERROR:. The recorded evidence wrapper ../rebuild-plan/r0-evidence/run_r0.sh enforces this. Running the normal tools/test.sh contracts includes other contracts; missing production dependencies must remain visible and cannot be counted as a pass.

Initial isolated result: 448 checks, zero failures on Godot4.6.3, contract-only agreement. See the separate R0 report for raw RED/GREEN and blocked full-suite classification.
