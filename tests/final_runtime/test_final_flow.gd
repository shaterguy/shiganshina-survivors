extends RefCounted
const Loot = preload("res://game/loot/loot_rules.gd")
const S = preload("res://tests/app_city_controller/controller_city_support.gd")
func run(t) -> void:
	var path := "res://game/app/final_evacuation_flow.gd"
	t.check(FileAccess.file_exists(path),"pure final flow exists for live-snapshot passage/dock proposals")
	if not FileAccess.file_exists(path): return
	var flow = load(path)
	var f := S.make(t)
	if f.is_empty(): return
	var app = f.app
	app.start_run(42)
	app.state.active_tick = 107999
	app.state.survival_tick = 107999
	app.state.player.position = [384.0,384.0]
	for index in range(Loot.FIELD_TICKS.size()):
		app.simulation._add_loot(app.state,Loot.field_spec(index),Vector2(384.0,384.0))
	var staged: Dictionary = f.runtime.refresh_coverage(app.state)
	t.check(staged.get("ok",false),"final flow fixture prepares real city geometry")
	if not staged.get("ok",false): app.free(); return
	app.simulation = staged.simulation; app.state = staged.state
	var events: Array = app._step_city_tick().events
	t.check(app.state.phase == "evacuation" and events.size() >= 2,"pure helper receives actual Director/Core final transition")
	var before: Dictionary = app.state.duplicate(true)
	var authority: Dictionary = app.game_save.duplicate(true)
	var result: Dictionary = flow.prepare(app.simulation,app.state,app.game_save,app.chapter)
	t.check(result.get("ok",false) and result.get("action") == "passage_selection","unselected final returns one passage selection candidate")
	if not result.get("ok",false) or not result.has("candidate"): app.free(); return
	t.check(app.state == before and app.game_save == authority,"proposal mutates neither live A nor saved authority")
	t.check(result.candidate.checkpoint.active_tick == 108000 and result.candidate.checkpoint.final_started_tick == 108000 and app.game_save.checkpoint.active_tick == 0,"candidate snapshots live tick rather than rewinding to old durable checkpoint")
	t.check(result.candidate.checkpoint.world.evacuation.size() == 3 and result.candidate.checkpoint.escape_zone == [0.0,0.0,0.0,0.0],"passage snapshot persists only exact existing evacuation fields and sentinel")
	app.free()
