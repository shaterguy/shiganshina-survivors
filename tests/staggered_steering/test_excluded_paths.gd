extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
const Director = preload("res://game/director/spawn_director.gd")
class OriginalMovement:
	extends "res://game/core/run_simulation.gd"
	# Exact movement body from fec0ec5; no steering argument is supplied.
	func _move_pursuing_enemy(state: Dictionary,entity: Dictionary,movement_targets: Variant = null) -> void:
		var position := _vec(entity.position)
		var direction := _direction_world(state,position,_vec(state.player.position),float(entity.radius),str(entity.id),movement_targets)
		entity.velocity = _array(direction*float(entity.speed))
		entity.position = _array(_move_world(state,position,_vec(entity.velocity)/TICKS_PER_SECOND,float(entity.radius)))
		if not direction.is_zero_approx(): entity.facing = _array(direction)
func run(t) -> void:
	for kind in ["finite","boss","final"]:
		var provider = F.City.new() if kind!="finite" else null
		var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter if provider!=null else F.F.v2_chapter()
		var sim = F.Core.new(provider)
		var state: Dictionary = sim.new_run(chapter,42,F.F.run_config())
		state.player.attack_ready_ticks = {"blade_slash":200000}
		var commands: Array[Dictionary] = []
		var hydration := {}
		if kind=="finite":
			commands.append({"command_id":"finite:walker","kind":"spawn_enemy","payload":{"entity_id":"finite:walker","enemy_id":"walker","position":[200.0,0.0],"spawned_tick":0}})
		else:
			state.player.position = [384.0,384.0]
			state.active_tick = 17999 if kind=="boss" else 107999
			state.survival_tick = state.active_tick
			for command in Director.new().plan(state,chapter):
				if command.kind in ["spawn_boss","begin_evacuation"]:
					command.origin_revision = state.world.origin_revision
					commands.append(command)
			hydration = F.HF.hydration(F.H.requirements(state,commands))
			t.check(sim.prepare_world(state,hydration,commands).get("ok",false),kind+" exact real boundary prepares")
		F.F.step(sim,state,Vector2.ZERO,commands)
		t.check(sim.step_status().get("ok",false) and state.entities.size()==1,kind+" actual spawn creates expected one actor")
		if state.entities.size()!=1: continue
		var oracle = OriginalMovement.new(provider)
		var restored: Dictionary = oracle.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration)
		t.check(restored.get("ok",false),kind+" existing checkpoint restores without schema/content changes")
		if not restored.get("ok",false): continue
		var other: Dictionary = restored.state
		if kind!="finite": t.check(oracle.prepare_world(other,hydration).get("ok",false),kind+" original-path oracle prepares")
		var pending_seen := false
		for i in 180:
			state.player.hp = float(state.player.max_hp); other.player.hp = float(other.player.max_hp)
			var a := F.F.step(sim,state,Vector2.ZERO)
			var b := F.F.step(oracle,other,Vector2.ZERO)
			t.check(sim.step_status().get("ok",false) and oracle.step_status().get("ok",false) and state==other and a==b,kind+" exact state/events equal original movement path")
			if state.entities[0].action_state!="move": pending_seen = true
		print("STEERING_EXCLUDED ",JSON.stringify({"kind":kind,"ticks":180,"pending_attack_seen":pending_seen,"state_equal":state==other}))
