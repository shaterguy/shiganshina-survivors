extends SceneTree
# Run only against an isolated, unmodified dev7 source copy. Output contains
# actual GameSaveStore bytes after normal Core ticks and actual controller save.
const Fixture = preload("res://tests/dev5_mobility_autosave/mobility_app_fixture.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var fixture = Fixture.new()
	var app = fixture.airborne(self,"legacy_capture","glide")
	if app == null: quit(1); return
	app.autosave_worker_enabled = false
	var seen := {}
	for tick in 64:
		var phase: String = app.state.player_mobility.phase
		if not seen.has(phase):
			app._save_checkpoint()
			var read: Dictionary = app.save_store.read_game()
			check(read.get("ok",false),"dev7 genuine phase persisted: "+phase)
			if not read.get("ok",false): break
			check(read.game_save.checkpoint.player_mobility.phase == phase,"saved phase matches live phase")
			var packet := {"source":"dev7:38b0cb1","provider":"shipped_city","game_save":read.game_save,"source_sha256":read.source_sha256}
			var path := OS.get_environment("CORRIDOR_FIXTURE_OUTPUT").path_join("legacy_city_"+phase+".json")
			var file := FileAccess.open(path,FileAccess.WRITE)
			file.store_string(JSON.stringify(packet,"",true,true)); file.close()
			seen[phase] = true
		if seen.size() == 5: break
		var step: Dictionary = app._step_city_tick()
		check(step.get("ok",false),"dev7 actual city tick succeeds")
		if not step.get("ok",false): break
	app.free()
	await create_timer(0.4).timeout
	print("LEGACY_CITY_CAPTURE ",JSON.stringify({"phases":seen.keys(),"failures":failures}))
	quit(0 if failures == 0 and seen.size() == 5 else 1)
