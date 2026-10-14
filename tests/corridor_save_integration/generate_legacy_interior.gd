extends SceneTree
const AppFixture = preload("res://tests/dev5_mobility_autosave/mobility_app_fixture.gd")
const MotionFixture = preload("res://tests/terrain_mobility/motion_fixture.gd")
var failures := 0
func check(value: bool, message: String) -> void:
	if not value: failures += 1; push_error(message)
func _initialize() -> void: call_deferred("run")
func write_packet(name: String, packet: Dictionary) -> void:
	var path := OS.get_environment("CORRIDOR_FIXTURE_OUTPUT").path_join(name)
	var file := FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(packet,"",true,true)); file.close()
func run() -> void:
	var f := MotionFixture.make(self)
	check(MotionFixture.reach(f,"over"),"legacy custom interior reaches genuine over")
	MotionFixture.step(f); MotionFixture.step(f)
	check(f.state.player_mobility.phase == "over","legacy custom interior stays over")
	write_packet("legacy_custom_over_interior.json",{"source":"dev7:38b0cb1","state":f.core.snapshot(f.state),"hydration":f.hydration})
	var helper = AppFixture.new()
	var app = helper.airborne(self,"interior_capture","over")
	if app == null: quit(1); return
	app.autosave_worker_enabled = false
	for tick in 2:
		check(app._step_city_tick().get("ok",false),"legacy actual city interior normal tick")
	check(app.state.player_mobility.phase == "over","legacy actual city stays over in interior")
	app._save_checkpoint()
	var read: Dictionary = app.save_store.read_game()
	check(read.get("ok",false),"legacy actual city interior save accepted")
	if read.get("ok",false): write_packet("legacy_city_over_interior.json",{"source":"dev7:38b0cb1","provider":"shipped_city","game_save":read.game_save,"source_sha256":read.source_sha256})
	app.free(); await create_timer(0.4).timeout
	print("LEGACY_INTERIOR_CAPTURE ",JSON.stringify({"failures":failures,"custom_position":f.state.player.position}))
	quit(0 if failures == 0 else 1)
