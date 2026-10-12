extends RefCounted
const S = preload("res://tests/final_runtime/final_support.gd")
const Flow = preload("res://game/app/final_evacuation_flow.gd")
func run(t) -> void:
	_windup(t)
	_busy_charge(t)
	_parked(t)
func _actor(state: Dictionary) -> Dictionary:
	for entity in state.get("entities",[]):
		if entity.enemy_id == "armored_titan": return entity
	return {}
func _windup(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,384.0])
	var original: Dictionary = _actor(app.state).duplicate(true)
	t.check(not original.is_empty() and original.action_state == "windup","actual final Director/Core creates one physically placed windup actor")
	if original.is_empty(): app.free(); return
	var warning: Dictionary = app.state.telegraphs[0].duplicate(true)
	app.advance_frame(1.0/60.0)
	var carried := _actor(app.state)
	t.check(app.state.world.stage == "dock" and app._final_error.is_empty() and not carried.is_empty(),"actual Controller saves actor-owned dock candidate instead of retiring final actor")
	if app.state.world.stage != "dock": app.free(); return
	t.check(app.state.entities.size() == 1 and carried.id == original.id and app._same_json(carried.position,app.chapter.authored_dock.final_actor_entry_position),"same final actor is installed once at validated authored dock anchor")
	t.check(carried.action_state == original.action_state and carried.action_started_tick == original.action_started_tick and carried.action_ends_tick == original.action_ends_tick,"handoff preserves action phase and its remaining warning deadline")
	t.check(app.state.telegraphs.size() == 1 and app.state.telegraphs[0].id == warning.id and app.state.telegraphs[0].active_from_tick == warning.active_from_tick and app.state.telegraphs[0].expires_tick == warning.expires_tick,"same owner warning survives once without rearming its deadline")
	t.check(app.state.telegraphs[0].get("behavior_attack",false) and str(app.state.telegraphs[0].source_id) == str(carried.id) and not app.state.telegraphs.any(func(h): return h.source_id == "armored"),"final actor is the sole warning producer and old remote circle is absent")
	t.check(app.state.final_started_tick == 108000 and carried.hp == carried.max_hp and app.state.stats.kills == 0 and app.state.reward_ids_claimed.is_empty(),"scene handoff never resets final clock or invents damage kill reward")
	var repeat: Dictionary = Flow.prepare(app.simulation,app.state,app.game_save,app.chapter)
	t.check(repeat.get("ok",false) and repeat.get("reason") == "already_applied","repeated handoff is a no-candidate no-actor-duplication operation")
	var saved_actor: Dictionary = app.game_save.checkpoint.entities[0].duplicate(true)
	var cold := S.make(t,f.directory,false)
	cold.app.request_resume()
	t.check(cold.app.state.world.stage == "dock" and cold.app.state.entities.size() == 1 and app._same_json(cold.app.state.entities[0],saved_actor),"actual cold resume retains same actor identity and remaining FSM deadline")
	cold.app.free(); app.free()
func _busy_charge(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,280.0])
	for tick in 200:
		app.state.player.hp = app.state.player.max_hp
		if _actor(app.state).get("action_state") == "attack": break
		app.advance_frame(1.0/60.0)
	var actor := _actor(app.state)
	t.check(actor.get("action_state") == "attack","actual city actor reaches active charge while player is outside passage")
	if actor.get("action_state") != "attack": app.free(); return
	var id = actor.id
	var deadline: int = actor.action_ends_tick
	app.state.player.position = [384.0,384.0]
	var tick: int = app.state.active_tick
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "city" and app.state.active_tick == tick+1 and app._final_intent.is_empty() and app._final_error.is_empty(),"overlapping passage during active charge waits without freezing timer or preparing a save")
	for frame in 200:
		app.state.player.hp = app.state.player.max_hp
		app.advance_frame(1.0/60.0)
		if app.state.world.stage == "dock" or not app._final_error.is_empty(): break
	t.check(app.state.world.stage == "dock" and app.state.active_tick <= deadline and app.state.final_started_tick == 108000,"original charge deadline reaches a safe physical dock seam with continuously running final clock")
	t.check(_actor(app.state).get("id") == id and app.state.entities.size() == 1 and S.count_actions(app,"dock_transition") == 1,"safe-seam admission preserves one actor and makes one dock transaction")
	app.free()

func _parked(t) -> void:
	var f := S.make(t,"",false)
	if f.is_empty(): return
	var app = f.app
	S.boundary(f,[384.0,280.0])
	var actor := _actor(app.state)
	var id = actor.id
	actor.position = [-1300.0,384.0]
	app.simulation._set_action(actor,"move",int(app.state.active_tick),0)
	app.state.telegraphs.clear()
	app.advance_frame(1.0/60.0)
	t.check(_actor(app.state).is_empty() and app.state.world.dormant.entities.size() == 1,"actual Controller parks quiescent final actor in one absolute v2 record")
	if not _actor(app.state).is_empty() or app.state.world.dormant.entities.size() != 1: app.free(); return
	var parked: Dictionary = app.state.world.dormant.entities[0].duplicate(true)
	app.state.player.position = [384.0,384.0]
	app.advance_frame(1.0/60.0)
	t.check(app.state.world.stage == "dock" and app._final_error.is_empty(),"actual Controller commits parked final actor through same dock boundary")
	if app.state.world.stage != "dock": app.free(); return
	t.check(app.state.world.dormant.entities.is_empty() and app.state.world.dormant.drops.is_empty() and app.state.entities.size() == 1 and _actor(app.state).id == id,"parked handoff consumes exact same dormant ID and installs one active actor")
	t.check(parked.record.id == id and _actor(app.state).action_state == "move" and app.state.telegraphs.is_empty() and app.state.final_started_tick == 108000,"dormant move seam does not invent or duplicate a warning or restart final clock")
	var cold := S.make(t,f.directory,false)
	cold.app.request_resume()
	t.check(cold.app.state.world.stage == "dock" and cold.app.state.entities.size() == 1 and _actor(cold.app.state).id == id and cold.app.state.world.dormant.entities.is_empty(),"cold dock reload contains one final actor and no retained dormant duplicate")
	cold.app.advance_frame(1.0/60.0)
	var resumed := _actor(cold.app.state)
	t.check(resumed.action_state == "windup" and resumed.action_ends_tick-cold.app.state.active_tick == 72 and cold.app.state.telegraphs.size() == 1,"first actual dock tick restarts physical pursuit with one full authored warning")
	cold.app.free(); app.free()
