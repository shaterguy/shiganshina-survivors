extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core_world/test_live_grabber_transaction.gd")
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
class UncoveredCore:
	extends "res://game/core/run_simulation.gd"
	var force_uncovered := false
	func _regenerate(state: Dictionary) -> void:
		super._regenerate(state)
		if force_uncovered: _role_query(state).sweep(_vec(state.player.position),Vector2(8000,0),7)
func run(t) -> void:
	for id in ["quadruped","stone_thrower"]:
		_city(t,id)
		_missing(t,id)
func _command(id: String) -> Dictionary:
	var c: Dictionary = G.new().command()
	c.payload.enemy_id = id
	return c
func _city(t,id: String) -> void:
	var f := G.new().fixture(t)
	var sim = f.sim
	var state: Dictionary = f.state
	F.step(sim,state,Vector2.ZERO,[_command(id)])
	t.check(sim.step_status().ok and state.enemy_attack_instances.size() == 1,"real generated city admits new role: "+id)
	if state.enemy_attack_instances.is_empty(): return
	var a: Dictionary = state.enemy_attack_instances[0].duplicate(true)
	for tick in range(2,int(a.recover_ends_tick)+1):
		F.step(sim,state,Vector2.ZERO)
		if not sim.step_status().ok:
			t.check(false,"city attack progresses without uncovered hold: "+id+" "+str(sim.step_status())); return
		if tick not in [a.active_from_tick-1,a.active_from_tick,a.active_from_tick+10,a.attack_ends_tick,a.recover_ends_tick-1,a.recover_ends_tick]: continue
		var needed: Dictionary = Helper.requirements(state)
		var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,needed.chunks)
		var restored := Core.new(City.new()).restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydrated.deltas)
		t.check(restored.get("ok",false) and restored.get("state",{}) == state,"city cold restore matches boundary: "+id+":"+str(tick))
		if tick != a.active_from_tick+10: continue
		var shifted := state.duplicate(true)
		shifted.world.origin_chunk = ["-1","0"]
		shifted.player.position[0] += 768.0
		for actor in shifted.entities:
			for key in ["position","locked_origin","locked_target"]: actor[key][0] += 768.0
		for attack in shifted.enemy_attack_instances:
			for key in ["locked_origin","locked_target"]: attack[key][0] += 768.0
		hydrated = f.disk.hydrate(shifted.world.delta_root,Helper.requirements(shifted).chunks)
		var fresh := Core.new(City.new())
		restored = fresh.restore(JSON.parse_string(JSON.stringify(shifted,"",true,true)),hydrated.deltas)
		t.check(restored.get("ok",false),"translated active city role validates: "+id)
		if not restored.get("ok",false): continue
		shifted = restored.state
		fresh.prepare_world(shifted,hydrated.deltas)
		var expected := state.duplicate(true)
		var warm_events := F.step(sim,expected,Vector2.ZERO)
		var cold_events := F.step(fresh,shifted,Vector2.ZERO)
		t.check(fresh.step_status().ok and shifted.entities == expected.entities and shifted.enemy_attack_instances == expected.enemy_attack_instances and cold_events == warm_events,"active role origin rebase keeps path cap motion and damage identity: "+id)
func _missing(t,id: String) -> void:
	var f := G.new().fixture(t)
	var sim := UncoveredCore.new(City.new())
	var state: Dictionary = f.state
	t.check(sim.prepare_world(state,f.hydration).ok,"missing-world fixture prepares: "+id)
	F.step(sim,state,Vector2.ZERO,[_command(id)])
	if state.enemy_attack_instances.is_empty(): t.check(false,"missing-world fixture owns role: "+id); return
	var before := state.duplicate(true)
	var view := sim.enemy_attack_view(state)
	sim.force_uncovered = true
	var events := F.step(sim,state,Vector2.ZERO)
	t.check(events.is_empty() and state == before and sim.step_status().get("error_code") == "world_not_ready" and sim.enemy_attack_view(state) == view,"missing terrain rolls clock motion damage and packet back: "+id)
	sim.force_uncovered = false
	t.check(sim.prepare_world(state,f.hydration).ok,"missing terrain requires new valid preparation: "+id)
	F.step(sim,state,Vector2.ZERO)
	t.check(sim.step_status().ok and state.active_tick == 2,"identical input resumes once after preparation: "+id)
