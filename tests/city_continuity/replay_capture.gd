extends SceneTree
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func _initialize() -> void:
	var path: String = OS.get_cmdline_user_args()[0]
	var payload: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var state: Dictionary = payload.get("state",payload.get("checkpoint",{}))
	var commands: Array[Dictionary] = []
	commands.assign(payload.get("commands",payload.get("pending_tick",{}).get("commands",[])))
	var core := Core.new(City.new())
	var needed := H.requirements(state,commands)
	if not needed.get("ok",false):
		print("CAPTURE_REQUIREMENTS ",needed)
		quit(1)
		return
	var hydration := F.hydration(needed)
	var restored := core.restore(state,hydration)
	if not restored.get("ok",false):
		print("CAPTURE_RESTORE ",restored)
		quit(1)
		return
	state = restored.state
	var prepared := core.prepare_world(state,hydration,commands)
	print("CAPTURE_PREPARE ",prepared)
	if not prepared.get("ok",false):
		quit(1)
		return
	core.step(state,Vector2.RIGHT,commands)
	print("CAPTURE_STEP ",JSON.stringify({"status":core.step_status(),"tick":state.active_tick,"origin":state.world.origin_chunk,"origin_revision":state.world.origin_revision,"player":state.player.position}))
	var after := core.restore(state,hydration)
	print("CAPTURE_AFTER_RESTORE ",after.get("ok",false)," ",after.get("error_code","")," canonical_equal=",after.get("state",{}) == state)
	quit(0 if after.get("ok",false) and core.step_status().get("ok",false) else 1)
