extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
class InterruptedLoad:
	extends "res://game/app/prepared_city_runtime.gd"
	var app
	var reason := "controller_lost"
	func prepare_load(game_save: Dictionary, commands: Array = []) -> Dictionary:
		var result := super.prepare_load(game_save,commands)
		app._latch_lifecycle_pause(reason)
		return result
func run(t) -> void:
	var f := S.make(t)
	if f.is_empty(): return
	f.app.start_run(42)
	var directory: String = f.directory
	f.app.free()
	var cold := S.make(t,directory)
	var app = cold.app
	var runtime := InterruptedLoad.new(cold.provider,cold.disk)
	runtime.app = app
	app._city_runtime = runtime
	app.request_resume()
	t.check(not app.state.is_empty() and "controller_lost" in app.state.pause_reasons,"controller loss during cold preparation survives explicit resume's earlier generation")
	t.check(not "controller_lost" in app.game_save.checkpoint.pause_reasons,"cold lifecycle overlay never alters confirmed saved candidate")
	app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == 0 and app.audio._music.stream_paused,"late cold-load lifecycle generation blocks next tick and audio")
	app.free()
