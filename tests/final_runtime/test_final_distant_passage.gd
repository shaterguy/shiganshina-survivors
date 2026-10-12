extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
func run(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f)
	var selected: Dictionary = app.state.world.evacuation.duplicate(true)
	for destination in [["20","0"],["-20","0"],["9007199254740993","-9007199254740994"]]:
		var relocated: Dictionary = app.state.duplicate(true)
		relocated.world.origin_chunk = destination.duplicate()
		relocated.world.origin_revision += 1
		relocated.player.position = [384.0,384.0]
		var prepared: Dictionary = f.runtime.refresh_coverage(relocated)
		t.check(prepared.get("ok",false),"distant final fixture prepares exact absolute origin "+str(destination))
		if not prepared.get("ok",false): continue
		app.simulation = prepared.simulation; app.state = prepared.state
		var tick: int = app.state.active_tick
		app.input_router.set_touch_vector(Vector2.RIGHT)
		app.advance_frame(1.0/60.0); app.advance_frame(1.0/60.0)
		t.check(app._final_error.is_empty() and app._final_intent.is_empty() and app.state.active_tick == tick+2,"offscreen selected passage never freezes actual Controller ticks at "+str(destination))
		t.check(app.state.world.evacuation == selected and app.state.world.stage == "city","distant origin preserves original passage identity instead of reselection")
		if not app._final_error.is_empty(): break
	app.free()
