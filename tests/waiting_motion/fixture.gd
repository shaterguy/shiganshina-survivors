extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Model = preload("res://game/combat/enemy_attack_model.gd")
const ROLES = ["stone_thrower","grabber","quadruped"]
static func make(t, positions: Array = [[100.0,0.0],[0.0,180.0],[-160.0,0.0]], geometry: Dictionary = {}) -> Dictionary:
	var chapter: Dictionary = F.chapter() if geometry.is_empty() else F.geometry_chapter(geometry,[0.0,0.0])
	var sim = Core.new(F.Current.new()) if geometry.is_empty() else F.geometry_sim(chapter)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	state.active_tick = 12000; state.survival_tick = 12000
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	var commands := []
	for i in ROLES.size(): commands.append(F.spawn("wait:"+str(i),positions[i],ROLES[i]))
	commands.append(F.spawn("pressure",[0.0,0.0],"walker"))
	F.step(sim,state,Vector2.ZERO,commands)
	t.check(sim.step_status().get("ok",false) and state.entities.size()==4,"real current Core creates three waiters and a legacy pressure body")
	t.check(state.enemy_attack_instances.is_empty() and sim.step_status().get("role_admission",{}).get("detail")=="observed_body_pressure","real safety budget denies attack under legacy body pressure")
	return {"sim":sim,"state":state,"chapter":chapter}
static func actor(state: Dictionary, id: String) -> Dictionary:
	for e in state.entities:
		if str(e.id)==id: return e
	return {}
static func point(e: Dictionary) -> Vector2:
	return Vector2(e.position[0],e.position[1])
static func step(f: Dictionary, move := Vector2.ZERO) -> Array:
	f.state.player.hp = float(f.state.player.max_hp)
	return F.step(f.sim,f.state,move)
static func row(f: Dictionary) -> Dictionary:
	var actors := []
	var overlap_pairs := []
	for e in f.state.entities:
		if not str(e.id).begins_with("wait:"): continue
		actors.append({"id":e.id,"role":e.enemy_id,"position":e.position.duplicate(),"velocity":e.velocity.duplicate(),"facing":e.facing.duplicate(),"state":e.action_state,"wait_since":e.role_wait_since,"retry_tick":e.role_retry_tick})
	for i in f.state.entities.size():
		for j in range(i+1,f.state.entities.size()):
			var a: Dictionary = f.state.entities[i]; var b: Dictionary = f.state.entities[j]
			var penetration := float(a.radius)+float(b.radius)-point(a).distance_to(point(b))
			if penetration > 0: overlap_pairs.append({"a":a.id,"b":b.id,"depth":penetration})
	return {"tick":f.state.active_tick,"actors":actors,"admission":f.sim.step_status().get("role_admission",{}).duplicate(true),"overlaps":overlap_pairs}
static func write(name: String, value: Variant) -> void:
	var file := FileAccess.open("res://../evidence/"+name,FileAccess.WRITE)
	file.store_string(JSON.stringify(value,"  ",true,true))
