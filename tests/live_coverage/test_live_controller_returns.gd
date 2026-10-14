extends RefCounted
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
class FaultRuntime:
	extends "res://game/app/prepared_city_runtime.gd"
	var mode := "missing_pair"
	var calls := 0
	var discarded: WeakRef
	func refresh_coverage(snapshot: Dictionary, commands: Array = []) -> Dictionary:
		calls += 1
		if mode == "missing_pair": return {"ok":true}
		if mode == "null_simulation": return {"ok":true,"simulation":null,"state":snapshot.duplicate(true)}
		if mode == "wrong_simulation": return {"ok":true,"simulation":RefCounted.new(),"state":snapshot.duplicate(true)}
		if mode == "empty_return": return {}
		if mode == "wrong_ok": return {"ok":"true"}
		var candidate: Dictionary = super.refresh_coverage(snapshot,commands)
		if not candidate.get("ok",false): return candidate
		discarded = weakref(candidate.simulation)
		if mode == "empty_state": candidate.state = {}
		elif mode == "missing_survival_tick": candidate.state.erase("survival_tick")
		elif mode == "changed_value": candidate.state.player.hp -= 1
		elif mode == "wrong_phase": candidate.state.phase = false
		elif mode == "paused_candidate": candidate.state.pause_reasons = ["manual"]
		else: candidate.state = false
		return candidate
func run(t) -> void:
	for mode in ["missing_pair","null_simulation","wrong_simulation","wrong_state","empty_return","wrong_ok","empty_state","wrong_phase","paused_candidate","missing_survival_tick","changed_value"]:
		var f := S.make(t)
		if f.is_empty(): return
		var app = f.app
		app.start_run(42)
		t.check(not app.state.is_empty(),"malformed-return case starts actual city controller")
		if app.state.is_empty(): app.free(); return
		app.state.player.position = [1920.0,384.0]
		app.input_router.set_touch_vector(Vector2.RIGHT)
		var a = app.simulation
		var state_bytes := var_to_bytes(app.state)
		var helper = a._streamed
		var geometry := var_to_bytes(helper._world._chunks)
		var attack := var_to_bytes(a._attack_view_cache)
		var authority := var_to_bytes(app.game_save)
		var disk := FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json"))
		var faulty := FaultRuntime.new(f.provider,f.disk)
		faulty.mode = mode
		app._city_runtime = faulty
		var result: Variant = app._step_city_tick()
		t.check(faulty.calls == 1,"malformed pair causes one refresh only: "+mode)
		t.check(result is Dictionary and not result.get("ok",false) and result.get("error_code") == "world_not_ready","malformed pair yields a structured world refusal: "+mode)
		t.check(app.simulation == a and var_to_bytes(app.state) == state_bytes,"malformed pair preserves A identity, state and RNG: "+mode)
		t.check(a._streamed == helper and var_to_bytes(helper._world._chunks) == geometry and var_to_bytes(a._attack_view_cache) == attack,"malformed pair preserves A helper, terrain and attack view: "+mode)
		t.check(var_to_bytes(app.game_save) == authority and FileAccess.get_file_as_bytes(f.directory.path_join("game_save.json")) == disk,"malformed pair preserves memory and disk authority: "+mode)
		t.check(app._city_step_error == "world_not_ready" and not app._pending_city_tick.is_empty(),"malformed pair retains held tick for explicit retry: "+mode)
		if faulty.discarded != null: t.check(faulty.discarded.get_ref() == null,"malformed pair discards private B: "+mode)
		app.free()
