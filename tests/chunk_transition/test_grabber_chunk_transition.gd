extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Runtime = preload("res://game/app/prepared_city_runtime.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const Director = preload("res://game/director/spawn_director.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	_mixed_controller(t)
func _snapshot() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://tests/chunk_transition/mixed_hold_snapshot.json"))
func _mixed_controller(t) -> void:
	# Exact observed Source24 state, without actor/HP/equipment/terrain edits.
	var snapshot := _snapshot()
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	app.state = snapshot.duplicate(true)
	app.input_router.set_touch_vector(Vector2.RIGHT)
	var commands: Array[Dictionary] = app.director.plan(app.state,app.chapter)
	t.check(snapshot.active_tick == 30256 and snapshot.player.position == [640.0,0.0] and commands.is_empty(),"exact observed failing input remains tick30256 x640 right without commands")
	var before: Dictionary = app.game_save.duplicate(true)
	var result: Dictionary = app._step_city_tick()
	print("CHUNK_TRANSITION_OBSERVED "+JSON.stringify({"before":30256,"after":app.state.active_tick,"position":app.state.player.position,"result":result},"",true,true))
	t.check(result.get("ok",false) and app.state.active_tick == 30257 and app.state.player.position[0] > 640.0,"actual Controller commits observed boundary tick instead of repeat world_not_ready")
	if not result.get("ok",false): app.free(); return
	t.check(app._pending_city_tick.is_empty() and app._city_step_error.is_empty() and app.game_save == before,"successful derived coverage retry clears hold without a save mutation")
	var cold: Dictionary = f.runtime.refresh_coverage(JSON.parse_string(JSON.stringify(app.state,"",true,true)))
	t.check(cold.get("ok",false) and cold.state == app.state,"post-boundary exact state cold-restores with its new real coverage")
	if not cold.get("ok",false): app.free(); return
	var cold_core = cold.simulation
	var cold_state: Dictionary = cold.state
	for index in 30:
		commands = app.director.plan(app.state,app.chapter)
		for command in commands:
			if H.spatial_command(command): command.origin_revision = app.state.world.origin_revision
		var events: Array = cold_core.step(cold_state,Vector2.RIGHT,commands)
		var status: Dictionary = cold_core.step_status()
		if status.get("error_code") == "world_not_ready":
			cold = f.runtime.refresh_coverage(cold_state,commands)
			if cold.get("ok",false):
				cold_core = cold.simulation; cold_state = cold.state
				events = cold_core.step(cold_state,Vector2.RIGHT,commands)
				status = cold_core.step_status()
		result = app._step_city_tick()
		t.check(result.get("ok",false) and status.get("ok",false),"actual Controller and cold restored Core advance boundary continuation "+str(index))
		if not result.get("ok",false) or not status.get("ok",false): break
		t.check(app.state == cold_state and result.events == events and app.simulation.enemy_attack_view(app.state) == cold_core.enemy_attack_view(cold_state),"warm/cold boundary continuation state events and attack packet match "+str(index))
	app.free()
