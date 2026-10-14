extends RefCounted
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
func run(t) -> void:
	if not F.available(t): return
	var s: Dictionary = F.make(t)
	if s.is_empty(): return
	t.check(s.state.has("player_mobility"),"new current run receives optional paired mobility authority without odm_dash")
	if not s.state.has("player_mobility"): return
	var before_rng: String = s.state.rng_state
	var before_growth: String = s.state.progression_rng_state
	var seen := {}
	var previous: Vector2 = F.vec(s.state.player.position)
	for tick in 50:
		F.step(s)
		var m: Dictionary = s.state.player_mobility
		seen[m.phase] = true
		var current: Vector2 = F.AF.Address.relative(s.state.world.origin_chunk,F.vec(s.state.player.position),["0","0"]).local
		t.check(current.x == 180.0 and current.y <= previous.y,"current input remains forward, never enemy homing or origin return")
		t.check(current.distance_to(previous) <= 8.0001,"accepted mobility step respects 480px/s fixed tick cap")
		t.check(s.state.player.invulnerable_until == 0,"mobility adds no invulnerability")
		previous = current
	t.check(seen.has_all(["boost","ground"]) and seen.size() == 2,"real Core traverses only boost and ground, with no roof phases")
	t.check(s.state.rng_state == before_rng and s.state.progression_rng_state == before_growth,"mobility domain never consumes gameplay or growth RNG")
	var final_states := []
	for fps in [30,60,120]:
		var replay: Dictionary = F.make(t)
		var accumulator := 0
		for frame in fps:
			accumulator += 60
			while accumulator >= fps:
				F.step(replay)
				accumulator -= fps
		t.check(replay.state.active_tick == 60,"frame schedule actually accepts all sixty active ticks")
		final_states.append(replay.state)
	t.check(F.same(final_states[0],final_states[1]) and F.same(final_states[1],final_states[2]),"30/60/120 display schedules produce identical sixty active ticks")
	var legacy: Dictionary = F.make(t,"dev4")
	t.check(not legacy.state.has("player_mobility"),"legacy provider receives no mobility authority")
	F.step(legacy)
	t.check(not legacy.state.has("player_mobility"),"legacy movement never inserts mobility")
	_live_role_ticks(t)
	_opposite_enemy(t)
	_damage(t)
	_path_kill_rewards(t)
func _damage(t) -> void:
	var s: Dictionary = F.make(t)
	var command: Dictionary = F.F.spawn("path_enemy",[180.0,243.0],"walker")
	command.origin_revision = 0
	var first_events: Array[Dictionary] = F.step(s,Vector2.UP,[command])
	t.check(not s.state.entities.is_empty(),"path attack fixture spawns actual enemy")
	if s.state.entities.is_empty(): return
	var hits: int = first_events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").size()
	for tick in 48:
		for event in F.step(s):
			if event.type == "damage" and event.payload.get("source_id") == "player_mobility": hits += 1
	t.check(hits == 1,"accepted swept path hits one enemy once per cast through Core hit_entity")
	var lethal: Dictionary = F.make(t)
	t.check(F.reach(lethal,"boost"),"lethal test reaches a real grounded boost")
	lethal.state.player.hp = 1.0
	var hazard: Dictionary = F.F.hazard("mobility_lethal","circle",{"origin":lethal.state.player.position.duplicate(),"radius":200.0})
	hazard.origin_revision = lethal.state.world.origin_revision
	var events: Array[Dictionary] = F.step(lethal,Vector2.UP,[hazard])
	t.check(lethal.state.phase == "dead","ordinary hazard remains lethal during mobility")
	t.check(events.filter(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility").is_empty(),"fatal tick emits no later mobility path damage")
	var snapshot: Dictionary = lethal.state.duplicate(true)
	t.check(F.step(lethal).is_empty() and F.same(lethal.state,snapshot),"terminal run cannot continue mobility or attack")

func _path_kill_rewards(t) -> void:
	for boss in [false,true]:
		var s: Dictionary = F.make(t,"dev5",18000 if boss else 0)
		var payload: Dictionary = {"entity_id":"mobility_reward","enemy_id":"boss_charger" if boss else "walker","position":[180.0,256.0] if boss else [180.0,248.0],"spawned_tick":int(s.state.active_tick)}
		if boss:
			payload.boss_id = "ch01_b05"
			payload.scheduled_tick = 18000
		var setup_events: Array[Dictionary] = []
		t.check(s.core._spawn(s.state,payload,boss,setup_events),"reward fixture uses actual Core spawn definition")
		if s.state.entities.is_empty(): continue
		var enemy: Dictionary = s.state.entities[0]
		t.check(enemy.position == payload.position,"reward target actually occupies the intended legal swept-path fixture")
		s.core._initialize_action(s.state,enemy)
		enemy.hp = 1.0
		s.state.player.xp = int(s.core._catalog.progression.base_xp)-1
		t.check(s.core.prepare_world(s.state,s.hydration).get("ok",false),"arranged low-health reward state passes full restore")
		var events: Array[Dictionary] = F.step(s)
		t.check(events.any(func(e): return e.type == "damage" and e.payload.get("source_id") == "player_mobility"),"path kill is an actual Core damage event")
		t.check(s.state.entities.is_empty() and s.state.stats.kills == 1,"path kill removes dead entity before snapshot")
		t.check(s.state.player.level > 1,"path kill collects close XP and opens legitimate level progression")
		if boss: t.check(s.state.tactical_seals == 1 and "boss:ch01_b05" in s.state.reward_ids_claimed,"path boss kill claims exactly one ordinary boss reward")
		t.check(s.core.restore(s.core.snapshot(s.state),s.hydration).get("ok",false),"immediate path-kill/level-up/boss-reward save is valid")
		var paused: Dictionary = s.state.duplicate(true)
		t.check(F.step(s).is_empty() and F.same(paused,s.state),"real path-kill upgrade offer freezes active tick and ground-plane authority")

func _opposite_enemy(t) -> void:
	var s: Dictionary = F.make(t)
	var spawn: Dictionary = F.F.spawn("behind_player",[180.0,300.0],"walker")
	spawn.origin_revision = 0
	F.step(s,Vector2.UP,[spawn])
	t.check(s.state.entities.size() == 1 and s.state.player_mobility.phase != "ground","opposite-direction enemy is present during actual cast")
	for tick in 35: F.step(s)
	t.check(F.AF.Address.relative(s.state.world.origin_chunk,F.vec(s.state.player.position),["0","0"]).local.x == 180.0 and F.AF.Address.relative(s.state.world.origin_chunk,F.vec(s.state.player.position),["0","0"]).local.y < 172.0,"enemy behind player never redirects or recalls directional mobility")
func _live_role_ticks(t) -> void:
	for role in ["grabber","quadruped","stone_thrower"]:
		var s: Dictionary = F.make(t)
		var spawn: Dictionary = F.F.spawn("live_role",[240.0,288.0],role)
		spawn.origin_revision = 0
		F.step(s,Vector2.UP,[spawn])
		t.check(s.state.entities.size() == 1,"live role coexists with genuine mobility cast: "+role)
		for tick in 12:
			var expected: int = int(s.state.active_tick)+1
			F.step(s)
			t.check(s.core.step_status().get("ok",false) and s.state.active_tick == expected,"pre-move role query accepts the in-progress active tick: "+role)
		t.check(s.core.restore(s.core.snapshot(s.state),s.hydration).get("ok",false),"live enemy navigation and boost save stay valid: "+role)
