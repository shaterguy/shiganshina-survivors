extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
const Core = preload("res://game/core/run_simulation.gd")
const H = preload("res://game/core/streamed_run_world.gd")
class NoPathHelper:
	extends "res://game/core/streamed_run_world.gd"
	func direction(_position: Vector2, _target: Vector2, _radius: float, _tick: int, _actor_id: String = "") -> Dictionary:
		return {"ok":true,"direction":Vector2.ZERO,"blocked":true,"deferred":true,"wait_ticks":0}
func run(t) -> void:
	_no_path(t)
	_open_road(t)
func _open_road(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,384.0])
	var actor: Dictionary = app.state.entities[0]
	var id = actor.id
	actor.position = [-384.0,384.0]
	actor.locked_origin = actor.position.duplicate()
	actor.locked_target = app.state.player.position.duplicate()
	app.simulation._set_action(actor,"move",int(app.state.active_tick),0)
	app.state.telegraphs.clear()
	var staged: Dictionary = f.runtime.refresh_coverage(app.state)
	t.check(staged.get("ok",false),"active move seam fixture prepares actual legal city actor outside420 attack radius")
	if not staged.get("ok",false): app.free(); return
	app.simulation = staged.simulation; app.state = staged.state
	var before: int = app.state.active_tick
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app.state.active_tick == before+1 and app._final_error.is_empty(),"quiescent active move cannot block actual physical passage admission")
	if app.state.world.stage != "dock": app.free(); return
	t.check(app.state.entities.size() == 1 and app.state.entities[0].id == id and app.state.world.dormant.entities.is_empty() and app.state.final_started_tick == 108000,"active move seam preserves one final actor and original timer")
	app.advance_frame(1.0/60.0)
	t.check(app.state.entities[0].action_state == "windup" and app.state.entities[0].action_ends_tick-app.state.active_tick == 72 and app.state.telegraphs.size() == 1,"active move dock arrival begins one full72tick warning on next real tick")
	app.free()

func _no_path(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,280.0])
	var actor: Dictionary = app.state.entities[0]
	var id = actor.id
	actor.position = [1152.0,-128.0]
	actor.locked_origin = actor.position.duplicate()
	actor.locked_target = app.state.player.position.duplicate()
	app.simulation._set_action(actor,"move",int(app.state.active_tick),0)
	app.state.telegraphs.clear()
	var needed: Dictionary = H.requirements(app.state)
	var hydration: Dictionary = f.disk.hydrate(app.state.world.delta_root,needed.chunks)
	var core := Core.new(f.provider,NoPathHelper.new(app.chapter.world_definitions))
	t.check(core.prepare_world(app.state,hydration.deltas).get("ok",false),"actual Controller no-path fixture uses real generated geometry and a controlled unavailable navigation route")
	app.simulation = core
	var contact: Dictionary = core._streamed.sweep(Vector2(1152,-128),Vector2(384,384)-Vector2(1152,-128),32)
	t.check(contact.get("ok",false) and contact.fraction < 1,"no-path actor and selected passage are physically separated by real city building")
	var before: int = app.state.active_tick
	for frame in 30: app.advance_frame(1.0/60.0)
	t.check(app.state.active_tick == before+30 and app.state.world.stage == "city" and app.state.entities[0].position == [1152.0,-128.0] and app.state.entities[0].action_state == "move" and app.state.telegraphs.is_empty(),"actual Controller advances30 city ticks while unavailable route keeps actor quiescent outside passage")
	app.state.player.position = [384.0,384.0]
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app.state.active_tick == before+31 and app._final_error.is_empty(),"no-path active move never strands actual Controller at physical passage")
	if app.state.world.stage != "dock": app.free(); return
	t.check(app.state.entities.size() == 1 and app.state.entities[0].id == id and app.state.final_started_tick == 108000 and S.count_actions(app,"dock_transition") == 1,"no-path dock candidate saves original actor and timer once")
	app.advance_frame(1.0/60.0)
	t.check(app.state.entities[0].action_state == "windup" and app.state.entities[0].action_ends_tick-app.state.active_tick == 72 and app.state.telegraphs.size() == 1,"no-path handoff resumes one authored warning without stale city anchors")
	app.free()
