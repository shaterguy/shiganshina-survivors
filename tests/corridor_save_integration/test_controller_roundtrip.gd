extends "res://tests/corridor_save_integration/save_fixture.gd"
const DefaultWorker = preload("res://tests/app_async_autosave/test_default_worker.gd")
func run(t) -> void:
	await _legacy_city_resume(t,"over",false)
	await _legacy_city_resume(t,"over_interior",false,true)
	await _legacy_city_resume(t,"land",true)
	_v2_active_roundtrip(t)
	await _ordinary_default_autosave(t)
	await t.create_timer(0.3).timeout
func _legacy_city_resume(t, phase: String, fail_write: bool, uncertain_write := false) -> void:
	var path := "res://tests/corridor_save_integration/fixtures/legacy_city_"+phase+".json"
	t.check(FileAccess.file_exists(path),"shipped-city dev7 save fixture is present: "+phase)
	if not FileAccess.file_exists(path): return
	var captured: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	t.check(captured.source == "dev7:38b0cb1" and captured.provider == "shipped_city","resume fixture provenance identifies shipped dev7 Core and city")
	var source: Dictionary = captured.game_save.checkpoint.duplicate(true)
	# Valid nonzero sentinels isolate preservation from naturally empty counters.
	source.stats.kills = 3
	source.stats.damage_dealt = 37.5
	source.player_mobility.hit_ids = ["migration-previous-hit"]
	var f := seed_save(t,source,City.new(),"city_"+phase,captured.game_save)
	if f.is_empty(): return
	var read: Dictionary = f.store.read_game()
	t.check(read.get("ok",false),"shipped-city sentinel-bearing v1 source passes actual full validation")
	if not read.get("ok",false): return
	var app = controller(t,f,true)
	if app == null: return
	t.check(app.state.is_empty() and not app.pending_checkpoint.is_empty() and app._startup_view.is_empty(),"cold controller offers migrated checkpoint without recovery/reset prompt")
	t.check(FileAccess.get_file_as_string(f.path) == f.text,"cold controller startup leaves original v1 source bytes unchanged")
	var revision: int = int(f.raw.store_revision)
	if fail_write: app.autosave_test_fault = {"stage":"write","return_error":true}
	if uncertain_write: app.autosave_test_fault = {"stage":"after_replace_before_return","return_error":true,"persist_read_failure":true}
	app.input_router.set_touch_vector(Vector2.UP)
	app.request_resume()
	t.check(not app.state.is_empty(),"actual Continue resumes legacy checkpoint through prepared authority")
	if app.state.is_empty(): app.free(); return
	assert_migration(t,source,app.state,app.simulation,"cold "+phase)
	t.check(app.input_router.sample_move() == Vector2.ZERO,"actual Continue clears stale joystick input")
	t.check(app.state.active_tick == source.active_tick and app.state.survival_tick == source.survival_tick,"Continue consumes no gameplay time while migrating")
	var live: Dictionary = app.simulation.snapshot(app.state)
	await drain(t,app)
	if uncertain_write:
		t.check(not app._autosave_unknown.is_empty(),"uncertain first migrated commit retains an exact reconciliation job")
		t.check(app.game_save.store_revision == revision and same(app.simulation.snapshot(app.state),live),"uncertain migrated save retains predecessor envelope and safe live state until reconciliation")
		t.check(FileAccess.get_file_as_string(f.path+".bak") == f.text,"uncertain post-replace migration still preserves exact original v1 backup")
		app.autosave_test_fault = {}
		app.retry_save_recovery()
		await drain(t,app)
	if fail_write:
		t.check(app._autosave_known_failure and not app._autosave_blocker.is_empty(),"failed first migrated autosave is surfaced as recoverable known failure")
		t.check(FileAccess.get_file_as_string(f.path) == f.text and app.game_save.store_revision == revision,"failed v2 publication retains exact old v1 authority and revision")
		t.check(same(app.simulation.snapshot(app.state),live),"failed migration save never rewinds the safe live position")
		app.autosave_test_fault = {}
		app.retry_save_recovery()
		await drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app._autosave_unknown.is_empty() and app._pending_transaction.is_empty(),"migrated default-worker autosave confirms without authority mismatch")
	t.check(app.game_save.store_revision == revision+1,"first migrated autosave advances exactly one durable revision")
	t.check(same(app.simulation.snapshot(app.state),live),"worker completion preserves full migrated live state")
	t.check(FileAccess.get_file_as_string(f.path+".bak") == f.text,"first v2 write preserves exact original v1 bytes as recoverable backup")
	read = app.save_store.read_game()
	t.check(read.get("ok",false) and same(read.get("game_save",{}),app.game_save),"fresh disk read equals committed canonical v2 envelope")
	if read.get("ok",false):
		t.check(read.game_save.profile.supply_credits == 431 and same(read.game_save.checkpoint.stats,source.stats),"v2 autosave preserves nonzero coins and run statistics")
		t.check(read.game_save.checkpoint.player_mobility.hit_ids == ["migration-previous-hit"] and read.game_save.checkpoint.rng_state == source.rng_state and read.game_save.checkpoint.progression_rng_state == source.progression_rng_state,"v2 autosave preserves hit IDs and both RNG streams")
		t.check(read.source_sha256 == FileAccess.get_file_as_string(f.path).sha256_text(),"committed read source hash binds exact new file")
	var position: Array = app.state.player.position.duplicate()
	var step: Dictionary = app._step_city_tick()
	t.check(step.get("ok",false),"first actual zero-input tick after migration succeeds")
	t.check(app.state.player_mobility.phase == "ground" and app.state.player.position == position and app.state.player.velocity == [0.0,0.0],"first resumed tick never continues old roof trajectory")
	t.check(app.state.active_tick == int(source.active_tick)+1 and app.state.survival_tick == int(source.survival_tick)+1,"first resumed tick advances each clock exactly once")
	app._save_checkpoint(); await drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app.game_save.store_revision == revision+2,"ordinary autosave after migrated gameplay remains valid")
	var latest: Dictionary = app.game_save.duplicate(true)
	app.free()
	var cold = controller(t,f,true)
	if cold == null: return
	t.check(same(cold.game_save,latest) and cold.pending_checkpoint.player_mobility.schema_version == 2,"second cold startup reopens exact committed v2 authority")
	cold.free()
func _v2_active_roundtrip(t) -> void:
	var scenario: Dictionary = CorridorFixture.make(t)
	if scenario.is_empty(): return
	CorridorFixture.step(scenario)
	t.check(scenario.state.player_mobility.get("schema_version") == 2 and scenario.state.player_mobility.phase == "boost","v2 roundtrip fixture is produced by a genuine paired corridor cast")
	if scenario.state.player_mobility.phase != "boost": return
	var captured: Dictionary = scenario.core.snapshot(scenario.state)
	var f := seed_save(t,captured,scenario.provider,"active_v2")
	if f.is_empty(): return
	var read: Dictionary = f.store.read_game()
	t.check(read.get("ok",false),"active v2 paired-anchor save is admitted by actual disk contracts")
	if not read.get("ok",false): return
	t.check(same(read.game_save.checkpoint,captured),"v2 read roundtrip retains exact boost path, pair, progress, and heading")
	t.check(f.runtime.prepare_load(read.game_save).get("ok",false),"active v2 prepare_load succeeds")
	var pair: Dictionary = f.runtime.confirm_candidate(f.store)
	t.check(pair.get("ok",false) and same(pair.get("state",{}),captured),"v2 prepared state roundtrip is exact, with no legacy migration")
	var app = controller(t,f)
	if app == null: return
	app.request_resume()
	t.check(not app.state.is_empty() and app.state.player_mobility.phase == "boost","active v2 controller resumes existing corridor boost before its next input tick")
	t.check(same(app.game_save.checkpoint.player_mobility,captured.player_mobility),"v2 synchronous Continue autosave preserves active pair exactly")
	var position: Array = app.state.player.position.duplicate()
	var step: Dictionary = app._step_city_tick()
	t.check(step.get("ok",false) and app.state.player_mobility.phase == "ground" and app.state.player.position == position,"v2 resumed zero input stops immediately on current ground point")
	app._save_checkpoint()
	t.check(app._pending_transaction.is_empty() and app.save_store.read_game().get("ok",false),"v2 stopped corridor remains saveable after controller input policy")
	app.free()
func _ordinary_default_autosave(t) -> void:
	var helper = DefaultWorker.new()
	var app = helper._fixture(t,"corridor_ordinary")
	if app == null: return
	var revision: int = app.game_save.store_revision
	var snapshot: Dictionary = app.simulation.snapshot(app.state)
	t.check(snapshot.player_mobility.schema_version == 2 and snapshot.player_mobility.phase == "ground","ordinary shipped new run starts with v2 ground state")
	app._save_checkpoint(); await drain(t,app)
	t.check(app._autosave_blocker.is_empty() and app.game_save.store_revision == revision+1,"ordinary shipped default-worker autosave commits v2 run once")
	var read: Dictionary = app.save_store.read_game()
	t.check(read.get("ok",false) and same(read.get("game_save",{}).get("checkpoint",{}),snapshot),"ordinary shipped autosave roundtrips complete state")
	app.free()
