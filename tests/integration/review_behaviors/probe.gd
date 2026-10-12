extends SceneTree
const Sim = preload("res://game/core/run_simulation.gd")
const Fixture = preload("res://tests/core/core_fixture.gd")
const Behavior = preload("res://tests/core/behavior_fixture.gd")
const Geometry = preload("res://game/combat/attack_geometry.gd")
var checks := 0
var failures := 0
var difference_diagnostics := 0
func _initialize() -> void:
	var sim = Sim.new()
	probe_valid_actions(sim)
	probe_source_death_active(sim)
	probe_corrupt_position(sim)
	probe_orphan_danger(sim)
	print("REVIEW_BEHAVIORS checks=%d failures=%d"%[checks,failures])
	quit(1 if failures else 0)
func expect(condition: bool, label: String, detail: Variant = null) -> void:
	checks += 1
	if not condition:
		failures += 1
		if failures<=12 or label in ["corrupt windup position rejected","orphan scripted hazard rejected"]:
			print("FAIL ",label," observed=",detail)
func roundtrip(state: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(state,"",true,"full_precision" in OS.get_cmdline_user_args()))
func probe_valid_actions(sim) -> void:
	var sampled := 0
	for enemy_id in Behavior.IDS:
		var state: Dictionary = Behavior.run_with_enemy(sim,enemy_id,[-70.0,0.0])
		var phases: Dictionary = {}
		for tick in 500:
			var actor: Dictionary = state.entities[0]
			var key := "%s:%d"%[actor.action_state,int(actor.pattern_index)]
			if not phases.has(key):
				phases[key] = true
				var saved: Dictionary = roundtrip(state)
				var restored: Dictionary = sim.restore(saved)
				expect(restored.ok,"valid action checkpoint accepted",{"id":enemy_id,"phase":actor.action_state})
				if restored.ok:
					expect(restored.state==state,"valid action roundtrip equal",enemy_id)
					if restored.state!=state and difference_diagnostics<10: compare(state,restored.state,enemy_id)
					var original: Dictionary = sim.snapshot(state)
					for replay_tick in 10:
						Fixture.step(sim,original,Vector2.DOWN,[])
						Fixture.step(sim,restored.state,Vector2.DOWN,[])
						expect(original==restored.state,"behavior replay from every action",{"id":enemy_id,"phase":actor.action_state})
				for reason in ["user","upgrade","rotation","background","controller_lost","slow_frame"]:
					var paused: Dictionary = sim.snapshot(state)
					sim.set_pause(paused,reason,true)
					var before: Dictionary = sim.snapshot(paused)
					Fixture.step(sim,paused,Vector2.ONE,[])
					expect(paused==before,"behavior pause freezes full state",{"id":enemy_id,"phase":actor.action_state,"reason":reason})
				sampled += 1
			if actor.action_state=="attack" and actor.attack_kind in ["charge","grab"]:
				var hazard: Dictionary = state.telegraphs[0]
				for direction in [Vector2.RIGHT,Vector2.LEFT,Vector2.UP,Vector2.DOWN]:
					var edge: Vector2 = Behavior.vec(actor.position)+direction*float(actor.radius)
					expect(Geometry.overlaps(hazard,edge,0.0),"physical rush body lies within advertised capsule",{"id":enemy_id,"edge":edge})
			Fixture.step(sim,state,Vector2.ZERO,[])
	print("VALID_ACTIONS sampled=%d ids=10 ticks_each=500"%sampled)
func probe_source_death_active(sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"brute",[-50.0,0.0])
	expect(Behavior.until_action(sim,state,"attack"),"active source death fixture reaches attack")
	state.entities[0].hp = 1.0
	state.equipment = {"blade_slash":5}
	state.player.invulnerable_until = 0
	var hp: float = state.player.hp
	Fixture.step(sim,state,Vector2.ZERO,[])
	expect(state.entities.is_empty() and state.telegraphs.is_empty() and state.player.hp==hp,"source death cancels active danger before player damage",state.telegraphs)
func probe_corrupt_position(sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"boss_charger",[-160.0,0.0])
	state.entities[0].position = [-160.0,200.0]
	state.player.position = [-154.0,200.0]
	var saved: Dictionary = roundtrip(state)
	var restored: Dictionary = sim.restore(saved)
	expect(not restored.ok,"corrupt windup position rejected",{"accepted":restored.ok})
	if restored.ok:
		var played: Dictionary = restored.state
		var hp: float = played.player.hp
		var hazard: Dictionary = played.telegraphs[0].duplicate(true)
		Behavior.until_action(sim,played,"attack")
		print("CORRUPT_POSITION accepted=true outside_warning=",not Geometry.overlaps(hazard,Behavior.vec(played.player.position),float(played.player.radius))," hp_before=",hp," hp_after=",played.player.hp," position=",played.entities[0].position)
func probe_orphan_danger(sim) -> void:
	var state: Dictionary = Behavior.run_with_enemy(sim,"brute",[-50.0,0.0])
	state.entities.clear()
	var saved: Dictionary = roundtrip(state)
	var restored: Dictionary = sim.restore(saved)
	expect(not restored.ok,"orphan scripted hazard rejected",{"accepted":restored.ok})
	if restored.ok:
		var played: Dictionary = restored.state
		var hp: float = played.player.hp
		while played.active_tick < played.telegraphs[0].active_from_tick:
			Fixture.step(sim,played,Vector2.ZERO,[])
		print("ORPHAN_DANGER accepted=true entities=",played.entities.size()," hp_before=",hp," hp_after=",played.player.hp)
func compare(a: Variant,b: Variant,path: String) -> void:
	if a is Dictionary and b is Dictionary:
		for key in a:
			if b.has(key): compare(a[key],b[key],path+"."+str(key))
	elif a is Array and b is Array:
		for i in mini(a.size(),b.size()): compare(a[i],b[i],path+"[%d]"%i)
	elif a != b:
		difference_diagnostics += 1
		if difference_diagnostics<=10: print("ROUNDTRIP_DIFF ",path," a=",a," b=",b," numerical_delta=",float(b)-float(a) if (a is float or a is int) and (b is float or b is int) else null)
