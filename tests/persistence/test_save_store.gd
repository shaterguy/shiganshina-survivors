extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
func run(t) -> void:
	var path := "res://game/persistence/save_store.gd"
	t.check(FileAccess.file_exists(path), "SaveStore exists")
	if not FileAccess.file_exists(path): return
	var script = load(path)
	t.check(script != null and script.can_instantiate(), "SaveStore compiles")
	if script == null or not script.can_instantiate(): return
	var directory := "user://test_save_" + str(OS.get_process_id())
	var store = script.new(directory)
	var chapter = load("res://game/director/chapter_catalog.gd").new().load_chapter("chapter_01_shiganshina").chapter
	var sim = load("res://game/core/run_simulation.gd").new()
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	var commands: Array[Dictionary] = []
	for i in range(17): sim.step(state,Vector2(0.13,-0.97),commands)
	var original_tick: int = state.active_tick
	t.check(store.save_checkpoint(state).ok, "checkpoint saved")
	var loaded: Dictionary = store.load_checkpoint()
	t.check(loaded.ok and loaded.snapshot.rng_state == state.rng_state, "checkpoint RNG roundtrip")
	t.check(loaded.snapshot.player.position == state.player.position,"checkpoint preserves exact engine-generated diagonal coordinates")
	state.active_tick = 1800
	state.survival_tick = 1800
	t.check(store.save_checkpoint(state).ok, "replacement checkpoint saved")
	var broken := FileAccess.open(directory.path_join("checkpoint.json"),FileAccess.WRITE)
	broken.store_string("{partial")
	broken.close()
	loaded = store.load_checkpoint()
	t.check(loaded.ok and loaded.snapshot.active_tick == original_tick and loaded.get("recovered",false), "interrupted save recovers previous checkpoint")
	var profile := {"schema_version":1,"settings":{"deadzone":0.25},"cleared_chapter_ids":["chapter_01_shiganshina"],"unlocked_character_ids":["garrison_01"],"best_runs":{}}
	t.check(store.save_profile(profile).ok, "profile saved")
	var restored: Dictionary = store.load_profile()
	t.check(restored.ok and restored.profile.settings.deadzone == 0.25 and restored.profile.cleared_chapter_ids == profile.cleared_chapter_ids, "profile progress preserved")
	t.check(not store.save_checkpoint({"phase":"broken"}).ok, "invalid checkpoint cannot overwrite good backup")

	profile.settings.deadzone = "wide"
	t.check(not store.save_profile(profile).ok, "malformed numeric setting rejected")
	profile.settings.deadzone = 0.99
	t.check(not store.save_profile(profile).ok, "out of range deadzone rejected")
