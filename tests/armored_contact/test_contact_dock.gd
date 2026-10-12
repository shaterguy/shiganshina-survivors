extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
const A = preload("res://tests/armored_actor/armored_support.gd")
const R = preload("res://tests/armored_actor/test_armored_rebase.gd")
const Core = preload("res://game/core/run_simulation.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Flow = preload("res://game/app/final_evacuation_flow.gd")
class NoPathHelper:
	extends "res://game/core/streamed_run_world.gd"
	func direction(_position: Vector2,_target: Vector2,_radius: float,_tick: int,_actor_id: String = "") -> Dictionary:
		return {"ok":true,"direction":Vector2.ZERO,"blocked":true,"deferred":true,"wait_ticks":0}
func run(t) -> void:
	for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN,Vector2(1,1).normalized(),Vector2(-1,1).normalized(),Vector2(1,-1).normalized(),Vector2(-1,-1).normalized()]:
		var f := R.new()._make(t)
		var actor := A.actor(f.state)
		f.state.telegraphs.clear()
		f.core._set_action(actor,"move",int(f.state.active_tick),0)
		actor.locked_direction = [direction.x,direction.y]
		var before: Dictionary = f.state.duplicate(true)
		var handoff: Dictionary = f.core.final_actor_handoff(f.state,f.chapter.authored_dock)
		var expect_blocked: bool = false
		t.check(handoff.get("error_code","") == "blocked_final_entry" if expect_blocked else handoff.get("ok",false),"inactive dock seam ignores only stale heading "+str(direction))
		t.check(f.state == before,"dock preflight is pure "+str(direction))
	_active_north_warning(t)
	_waiting_controller(t)
func _waiting_controller(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,280.0])
	var actor: Dictionary = app.state.entities[0]
	var id = actor.id
	actor.position = [1152.0,-128.0]
	actor.locked_origin = actor.position.duplicate()
	actor.locked_target = app.state.player.position.duplicate()
	actor.locked_direction = [0.0,-1.0]
	app.simulation._set_action(actor,"move",int(app.state.active_tick),0)
	app.state.telegraphs.clear()
	var needed: Dictionary = H.requirements(app.state)
	var hydration: Dictionary = f.disk.hydrate(app.state.world.delta_root,needed.chunks)
	var core := Core.new(f.provider,NoPathHelper.new(app.chapter.world_definitions))
	t.check(core.prepare_world(app.state,hydration.deltas).get("ok",false),"north no-path Controller fixture is an actual valid city state")
	app.simulation = core
	app.state.player.position = [384.0,384.0]
	var before_tick: int = app.state.active_tick
	for i in 300:
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
		t.check(app._final_error.is_empty(),"blocked entry stays reevaluable waiting without Controller error "+str(i))
		if app.state.world.stage == "dock": break
	t.check(app.state.active_tick > before_tick and app.state.final_started_tick == 108000 and app.state.entities[0].id == id,"waiting preserves ID and original75second clock")
	t.check(app.state.world.stage == "dock","north-facing quiescent no-path actor cannot permanently strand actual Controller at passage")
	print("NORTH_DOCK_WAIT ",JSON.stringify({"tick":app.state.active_tick,"stage":app.state.world.stage,"actor_id":app.state.entities[0].id,"direction":app.state.entities[0].locked_direction,"final_started_tick":app.state.final_started_tick,"error":app._final_error}))
	app.free()

func _active_north_warning(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,280.0])
	var actor: Dictionary = app.state.entities[0]
	actor.position = [384.0,584.0]
	actor.locked_origin = actor.position.duplicate()
	actor.locked_target = [384.0,384.0]
	app.state.player.position = [384.0,384.0]
	app.state.telegraphs.clear()
	app.simulation._set_action(actor,"move",int(app.state.active_tick),0)
	actor.next_action_tick = app.state.active_tick
	var staged: Dictionary = f.runtime.refresh_coverage(app.state)
	t.check(staged.get("ok",false),"active north warning starts from legal authored city road")
	if not staged.get("ok",false): app.free(); return
	app.simulation = staged.simulation; app.state = staged.state
	# Produce the actual city warning first, so transfer can be compared against
	# its original identity and clock rather than inferred after teleportation.
	A.step({"core":app.simulation,"state":app.state,"chapter":app.chapter})
	actor = app.state.entities[0]
	t.check(actor.action_state == "windup" and actor.locked_direction == [0.0,-1.0] and app.state.world.stage == "city","north warning is created in actual city before handoff")
	var id = actor.id
	var deadline: int = actor.action_ends_tick
	var warning_id = app.state.telegraphs[0].id
	var warning_start: int = app.state.telegraphs[0].active_from_tick
	var warning_end: int = app.state.telegraphs[0].expires_tick
	app.advance_frame(1.0/60.0)
	actor = app.state.entities[0]
	t.check(app.state.world.stage == "city" and actor.position == [384.0,584.0],"preparation97 north warning stays in city because dock bounds would be penetrated17px")
	for i in 20:
		app.advance_frame(1.0/60.0)
		actor = app.state.entities[0]
		t.check(actor.id == id and actor.action_ends_tick == deadline and actor.locked_direction == [0.0,-1.0] and app.state.telegraphs[0].id == warning_id and app.state.telegraphs[0].active_from_tick == warning_start and app.state.telegraphs[0].expires_tick == warning_end and app._final_error.is_empty(),"blocked dock waiting preserves warning identity/direction/deadline "+str(i))
	t.check(app.state.world.stage == "city" and app.state.entities[0].id == id and app.state.final_started_tick == 108000 and S.count_actions(app,"dock_transition") == 0,"blocked warning stays live with original75second clock and no premature commit")
	var transitions := []
	for i in 160:
		var old_phase: String = app.state.entities[0].action_state
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
		actor = app.state.entities[0]
		if old_phase != actor.action_state: transitions.append({"tick":app.state.active_tick,"phase":actor.action_state})
		if app.state.world.stage == "dock": break
	t.check(app.state.world.stage == "dock" and actor.action_state == "brake" and actor.id == id and app.state.final_started_tick == 108000 and S.count_actions(app,"dock_transition") == 1,"original active warning completes its real attack then hands off once in brake")
	t.check(transitions.any(func(x): return x.phase == "attack") and app.state.active_tick == 108133,"waiting never cancels/reset warning and transfers at natural brake108133")
	print("PREPARATION97_DOCK_TRANSITIONS ",JSON.stringify(transitions))
	print("ACTIVE_NORTH_DOCK ",JSON.stringify({"tick":app.state.active_tick,"warning_end":deadline,"stage":app.state.world.stage,"actor":app.state.entities[0].action_state,"id":id}))
	app.free()
