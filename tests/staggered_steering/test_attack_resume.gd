extends RefCounted
const F = preload("res://tests/staggered_steering/fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
func run(t) -> void:
	var rows: Array = []
	for enemy in ["runner","brute","grabber","quadruped","stone_thrower"]:
		var f := F.make(t,enemy,"attack:"+enemy)
		if f.is_empty(): continue
		var state: Dictionary = f.state
		var actor: Dictionary = state.entities[0]
		state.telegraphs.clear(); state.enemy_attack_instances.clear()
		f.sim._set_action(actor,"move",int(state.active_tick),0)
		actor.attack_kind = "none"
		if f.sim._is_live_role(actor):
			actor.role_wait_since = -1; actor.role_retry_tick = 0; actor.role_hand_reach = -1.0; actor.pattern_index = 0
		actor.position = [384.0,384.0]
		actor.velocity = [0.0,0.0]
		actor.locked_origin = actor.position.duplicate()
		actor.next_action_tick = int(state.active_tick)
		var range_value: float = float(f.sim._role_profile(enemy).trigger_range) if f.sim._is_live_role(actor) else float(Core.Behaviors.profile(actor,state.rules.enemy_catalog).trigger_range)
		state.player.position = [384.0+minf(range_value-1.0,100.0),384.0]
		actor.locked_target = state.player.position.duplicate()
		t.check(f.sim.prepare_world(state,F.HF.hydration(F.H.requirements(state))).get("ok",false),enemy+" actual attack fixture restores")
		var seen_attack := false
		var resumed := false
		var phases := {}
		var damaged := 0
		for i in 420:
			state.player.hp = float(state.player.max_hp)
			var events := F.F.step(f.sim,state,Vector2.ZERO)
			if not f.sim.step_status().get("ok",false): t.check(false,enemy+" attack tick must accept"); break
			actor = state.entities[0]
			phases[actor.action_state] = true
			for event in events:
				if event.type == "damage": damaged += 1
			if actor.action_state != "move": seen_attack = true
			if seen_attack and actor.action_state == "move":
				t.check(f.sim._vec(actor.velocity).is_zero_approx(),enemy+" actual attack-to-move clears residual velocity")
				# Reposition target only: following tick must compute from current
				# legal/direct route with no residual rush velocity reuse.
				var point: Vector2 = f.sim._vec(actor.position)
				state.player.position = [point.x-250.0,point.y]
				if not f.sim._is_live_role(actor): actor.next_action_tick = int(state.active_tick)+1000
				var expected: Vector2 = f.sim._direction_world(state,point,f.sim._vec(state.player.position),float(actor.radius),str(actor.id))*float(actor.speed)
				F.clear(f.sim)
				F.F.step(f.sim,state,Vector2.ZERO)
				t.check(f.sim.step_status().get("ok",false) and f.sim._vec(state.entities[0].velocity).is_equal_approx(expected),enemy+" first resumed movement computes fresh pursuit velocity")
				resumed = true; break
		t.check(seen_attack and resumed and phases.has("windup") and phases.has("attack") and phases.has("recover"),enemy+" actual complete warning/attack/recovery chain remains active")
		rows.append({"enemy":enemy,"phases":phases,"resumed":resumed,"damage_events":damaged})
	print("STEERING_ATTACK_RESUME ",JSON.stringify(rows))
