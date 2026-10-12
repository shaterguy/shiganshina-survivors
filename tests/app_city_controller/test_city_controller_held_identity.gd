extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
const Coverage = preload("res://tests/app_city_controller/test_city_controller_coverage.gd")
class StaleDirector:
	extends "res://game/director/spawn_director.gd"
	var plans := 0
	func plan(state: Dictionary, _chapter: Dictionary) -> Array[Dictionary]:
		plans += 1
		return [{"command_id":"old-origin-spawn","kind":"spawn_enemy","origin_revision":state.world.origin_revision+1,"payload":{"entity_id":1,"enemy_id":"walker","position":[150,0],"spawned_tick":state.active_tick+1}}]
func run(t) -> void:
	_stale_held_state(t)
	_stale_origin_command(t)
func _stale_held_state(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var runtime := Coverage.ControlledRuntime.new(f.provider,f.disk)
	app._city_runtime = runtime
	app.state.player.position = [1920.0,384.0]
	app.advance_frame(1.0/60.0)
	t.check(not app._pending_city_tick.is_empty(),"identity fixture retains actual refused city tick")
	app.state.world.origin_revision += 1
	var before: Dictionary = app.state.duplicate(true)
	app.request_resume()
	t.check(app._city_step_error == "stale_world_tick" and app._pending_city_tick.is_empty(),"explicit retry refuses packet after local origin/state identity changed")
	t.check(app.state == before and runtime.refreshes == 1,"stale retained input never reaches new-origin private preparation or tick")
	app.free()
func _stale_origin_command(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	var director := StaleDirector.new()
	var runtime := Coverage.ControlledRuntime.new(f.provider,f.disk)
	app.director = director
	app._city_runtime = runtime
	var before: Dictionary = app.state.duplicate(true)
	app.advance_frame(1.0/60.0)
	t.check(app._city_step_error == "stale_origin_revision" and app.state == before,"controller never overwrites an explicit stale command origin stamp")
	app.advance_frame(1.0)
	app.request_resume()
	t.check(runtime.refreshes == 0 and director.plans == 1 and app.state == before,"non-coverage refusal is held, never replanned or sent through world refresh")
	app.free()
