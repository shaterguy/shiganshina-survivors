extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Director = preload("res://game/presentation/combat_vfx_director.gd")
const Current = preload("res://tests/core/current_combat_provider.gd")
class HitObserver extends "res://game/core/run_simulation.gd":
	var actual_hit_position: Array = []
	func _hit_entity(state: Dictionary, entity: Dictionary, damage: float, source: String, events: Array[Dictionary], boss_rewards: Array[Dictionary], attack_id: String = "") -> void:
		actual_hit_position = entity.position.duplicate()
		super._hit_entity(state,entity,damage,source,events,boss_rewards,attack_id)
func run(t) -> void:
	var core := HitObserver.new(Current.new())
	var state: Dictionary = core.new_run(F.chapter(),42,F.run_config())
	state.player.attack_ready_ticks.blade_slash = 2
	F.step(core,state,Vector2.ZERO,[F.spawn("hit-position-target",[40,0],"brute")])
	t.check(state.entities.size() == 1,"hit-position fixture creates real target")
	if state.entities.is_empty(): return
	state.entities[0].hp = 12.0
	var events := F.step(core,state,Vector2.ZERO)
	var hits := F.types(events,"damage").filter(func(event): return event.payload.target_id == "hit-position-target")
	t.check(hits.size() == 1 and state.entities.is_empty(),"real killing hit removes target from successful snapshot")
	if hits.size() != 1: return
	t.check(hits[0].payload.has("position"),"damage event keeps exact hit coordinates after target removal")
	if not hits[0].payload.has("position"): return
	t.check(hits[0].payload.position == core.actual_hit_position,"hit coordinates agree with actual collision-time position, not later attracted XP")
	var director := Director.new()
	director._damage(hits[0].payload,state.active_tick)
	t.check(director._effects.size() == 1 and director._effects[0].coordinate_space == "world","death spark does not depend on a removed actor")
	t.check(director._effects[0].origin == Vector2(hits[0].payload.position[0],hits[0].payload.position[1]),"death spark uses actual hit position")
	var restored: Dictionary = core.restore(JSON.parse_string(JSON.stringify(core.snapshot(state),"",true,true)))
	t.check(restored.get("ok",false),"transient hit coordinates require no save schema change")
	if restored.get("ok",false):
		var warm := F.step(core,state,Vector2.ZERO)
		var cold := F.step(core,restored.state,Vector2.ZERO)
		t.check(warm == cold and state == restored.state,"post-kill cold restore replays no old damage event")
	# Direct event ownership boundary: a living target may move after emission.
	var entity := {"id":"moving-target","enemy_id":"walker","hp":100.0,"position":[45.0,12.0],"xp":1,"boss_id":""}
	var emitted: Array[Dictionary] = []
	var rewards: Array[Dictionary] = []
	core._hit_entity(state,entity,3.0,"blade_slash",emitted,rewards,"probe")
	entity.position[0] = 99.0
	t.check(emitted[0].payload.position == [45.0,12.0],"damage owns its position array rather than later actor mutations")
