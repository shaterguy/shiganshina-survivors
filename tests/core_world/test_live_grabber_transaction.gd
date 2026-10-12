extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core/test_live_grabber.gd")
class LateHelper:
	extends "res://game/core/streamed_run_world.gd"
	var late := false
	func fresh(): return LateHelper.new(_definitions)
	func sweep(origin: Vector2,delta: Vector2,radius: float) -> Dictionary:
		if late: return _query_result(failure("world_not_ready"))
		return super.sweep(origin,delta,radius)
class LateCore:
	extends "res://game/core/run_simulation.gd"
	var fail_after_damage := false
	func _regenerate(state: Dictionary) -> void:
		super._regenerate(state)
		if fail_after_damage:
			_streamed.late = true
			_streamed.sweep(_vec(state.player.position),Vector2.ZERO,8.0)
func fixture(t, late := false) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var sim = LateCore.new(provider,LateHelper.new(chapter.world_definitions)) if late else Core.new(provider)
	var state: Dictionary = sim.new_run(chapter,42,F.run_config())
	state.player.position = [554.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":2147483647}
	var disk := Disk.new("/tmp/live_grabber_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var created: Dictionary = disk.prepare(state.world.delta_root,[],0)
	var needed: Dictionary = Helper.requirements(state)
	var hydrated: Dictionary = disk.hydrate(state.world.delta_root,needed.chunks)
	var ready: Dictionary = sim.prepare_world(state,hydrated.deltas)
	t.check(created.ok and needed.ok and hydrated.ok and ready.ok,"actual streamed role fixture is prepared and disk hydrated")
	return {"sim":sim,"state":state,"disk":disk,"hydration":hydrated.deltas,"chapter":chapter}
func command(point: Array = [384.0,384.0]) -> Dictionary:
	var result := G.spawn(77,point)
	result.origin_revision = 0
	return result
func run(t) -> void:
	_atomic_late_failure(t)
	_cold_rebase(t)
	_cap_removal(t)
	_near_wall_normal_rejection(t)
	_population_retirement_rebase(t)
	_diagonal_cap_roundtrip(t)
func _atomic_late_failure(t) -> void:
	var f := fixture(t,true); var sim = f.sim; var state: Dictionary = f.state
	F.step(sim,state,Vector2.ZERO,[command()])
	t.check(state.enemy_attack_instances.size() == 1,"actual streamed spawn starts hand attack")
	if state.enemy_attack_instances.is_empty(): print("CITY_ADMISSION ",sim.step_status()); return
	while state.active_tick < 69: F.step(sim,state,Vector2.ZERO)
	var before := state.duplicate(true)
	var view: Dictionary = sim.enemy_attack_view(state)
	sim.fail_after_damage = true
	var events := F.step(sim,state,Vector2.ZERO)
	t.check(events.is_empty() and state == before and not sim.step_status().ok,"late real sweep failure rolls HP clock serial owner wait and nested ledger back atomically")
	t.check(sim.enemy_attack_view(state) == view,"failed tick never publishes candidate hand packet")
	sim.fail_after_damage = false
	t.check(sim.prepare_world(state,f.hydration).ok,"fresh preparation clears late backend failure through authorized boundary")
	events = F.step(sim,state,Vector2.ZERO)
	t.check(state.active_tick == 70 and F.types(events,"damage").size() == 1 and state.enemy_attack_instances[0].hit_target_ids == ["player"],"same input retry delivers accepted hand hit exactly once")
func _cold_rebase(t) -> void:
	var f := fixture(t); var sim = f.sim; var state: Dictionary = f.state
	F.step(sim,state,Vector2.ZERO,[command()])
	if state.enemy_attack_instances.is_empty(): t.check(false,"rebase starts with real attack"); return
	for index in 65: F.step(sim,state,Vector2.ZERO)
	# Translation-only representation arrangement preserves the same absolute city.
	var shifted := state.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.player.position[0] += 768.0
	for actor in shifted.entities:
		for key in ["position","locked_origin","locked_target"]: actor[key][0] += 768.0
	for attack in shifted.enemy_attack_instances:
		for key in ["locked_origin","locked_target"]: attack[key][0] += 768.0
	var hydration: Dictionary = f.disk.hydrate(shifted.world.delta_root,Helper.requirements(shifted).chunks)
	var fresh := Core.new(City.new())
	var restored := fresh.restore(JSON.parse_string(JSON.stringify(shifted,"",true,true)),hydration.deltas)
	t.check(restored.get("ok",false),"cold role restores translated active raw attack and unchanged reach")
	if not restored.get("ok",false): print("ROLE_RESTORE ",restored); return
	shifted = restored.state
	t.check(fresh.prepare_world(shifted,hydration.deltas).ok,"cold role packet uses restored prepared world")
	var old_cap: float = shifted.entities[0].role_hand_reach
	var a := F.step(sim,state,Vector2.ZERO)
	var b := F.step(fresh,shifted,Vector2.ZERO)
	t.check(fresh.step_status().ok and shifted.world.origin_revision == 1,"live active grabber crosses normal origin rebase boundary")
	t.check(shifted.entities[0].role_hand_reach == old_cap and shifted.entities[0].position == state.entities[0].position and shifted.enemy_attack_instances == state.enemy_attack_instances and a == b,"rebase preserves fixed torso clock identity ledger and scalar cap")
	t.check(fresh.enemy_attack_view(shifted).attacks == sim.enemy_attack_view(state).attacks,"rebased cold hand packet matches uninterrupted authority")
func _cap_removal(t) -> void:
	var f := fixture(t); var sim = f.sim; var state: Dictionary = f.state
	var props: Array = sim._streamed.props_query(Rect2(0,0,768,768)).props
	var chosen := {}; var origin := Vector2.ZERO; var target := Vector2.ZERO
	for prop in props:
		if not prop.destructible: continue
		var box: Rect2 = prop.ground_footprint
		origin = Vector2(box.position.x-90,box.get_center().y)
		target = origin+Vector2(60,0)
		if not sim._streamed.walkable(origin,22).get("walkable",false) or not sim._streamed.walkable(target,8).get("walkable",false): continue
		var sweep: Dictionary = sim._streamed.sweep(origin,Vector2(210,0),22)
		if sweep.ok and sweep.fraction < 1.0: chosen = prop; break
	t.check(not chosen.is_empty(),"actual streamed destructible hand blocker found")
	if chosen.is_empty(): return
	state.player.position = [target.x,target.y]
	t.check(sim.prepare_world(state,f.hydration).ok,"clipped fixture remains actual Core-valid")
	F.step(sim,state,Vector2.ZERO,[command([origin.x,origin.y])])
	t.check(state.enemy_attack_instances.size() == 1,"clipped attack has authoritative saved owner")
	if state.enemy_attack_instances.is_empty(): print("CAP_ADMISSION ",sim.step_status()); return
	var cap: float = state.entities[0].role_hand_reach
	var id: String = state.enemy_attack_instances[0].attack_id
	var remote := {}
	for prop in props:
		if prop.destructible and prop.prop_id != chosen.prop_id and prop.ground_footprint.get_center().distance_to(origin) > 250: remote = prop; break
	t.check(not remote.is_empty(),"distant destruction fixture exists")
	if remote.is_empty(): return
	for prop in [remote,chosen]:
		state.world = state.world.duplicate(true)
		state.world.world_revision += 1
		state.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":prop.slot_id,"hp":0,"destroyed":true}]}]
		var ready: Dictionary = sim.prepare_world(state,f.hydration)
		t.check(ready.ok,"world change prepares exact saved hand without recapping")
		if not ready.ok: print("CAP_PREPARE ",ready); return
		F.step(sim,state,Vector2.ZERO)
		t.check(state.entities[0].role_hand_reach == cap and state.enemy_attack_instances[0].attack_id == id,"remote/local destruction keeps ownership clock and first clipped cap")
	var cold := Core.new(City.new())
	var restored: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),f.hydration)
	t.check(restored.get("ok",false) and cold.prepare_world(restored.state,f.hydration).ok,"cold restore after blocker removal keeps original announced reach")
	if restored.get("ok",false):
		var endpoint: Array = cold.enemy_attack_view(restored.state).attacks[0].hand_pose.warning_end
		t.check(Vector2(endpoint[0],endpoint[1]).distance_to(origin) <= cap+0.001,"cold warning cannot expand after local wall is removed")
func _near_wall_normal_rejection(t) -> void:
	var f := fixture(t); var sim = f.sim; var state: Dictionary = f.state
	var found := false
	for prop in sim._streamed.props_query(Rect2(0,0,768,768)).props:
		if (int(prop.collision_mask)&3) == 0: continue
		var box: Rect2 = prop.ground_footprint
		var origin := Vector2(box.position.x-21.0,box.get_center().y)
		var target := origin-Vector2(100,0)
		if not sim._streamed.walkable(origin,20).get("walkable",false) or sim._streamed.walkable(origin,22).get("walkable",true) or not sim._streamed.walkable(target,8).get("walkable",false): continue
		state.player.position = [target.x,target.y]
		if not sim.prepare_world(state,f.hydration).ok: continue
		F.step(sim,state,Vector2.ZERO,[command([origin.x,origin.y])])
		t.check(sim.step_status().ok and state.active_tick == 1 and state.entities.size() == 1,"body20/hand22 wall mismatch is normal rejection, not frozen transaction")
		t.check(state.enemy_attack_instances.is_empty() and Vector2(state.entities[0].position[0],state.entities[0].position[1]).distance_to(origin)>0,"invalid hand origin continues body movement away from wall")
		for index in 20: F.step(sim,state,Vector2.ZERO)
		t.check(state.active_tick == 21 and state.enemy_attack_instances.size() == 1,"wall-near actor can later begin a full warned attack")
		found = true; break
	t.check(found,"real wall-near radius boundary fixture found")

func _population_retirement_rebase(t) -> void:
	var f := fixture(t); var sim = f.sim; var state: Dictionary = f.state
	F.step(sim,state,Vector2.ZERO,[command([300.0,384.0])])
	t.check(state.entities.size() == 1 and state.entities[0].action_state == "move" and state.enemy_attack_instances.is_empty(),"retirement fixture starts as ordinary quiescent grabber")
	# Arrange an offscreen quiescent source and an equivalent translated city
	# representation. Population retirement and origin rebase must commit together.
	state.entities[0].position = [-1152.0,384.0]
	state.world.origin_chunk = ["-1","0"]
	state.player.position[0] += 768.0
	for key in ["position","locked_origin","locked_target"]: state.entities[0][key][0] += 768.0
	var needed: Dictionary = Helper.requirements(state)
	var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,needed.chunks)
	t.check(needed.ok and hydrated.ok and sim.prepare_world(state,hydrated.deltas).ok,"actual city prepares retirement and rebase in the same transaction")
	var missing := state.duplicate(true)
	missing.entities.clear()
	t.check(not sim._reconcile_rebased_motion(state,missing,sim._streamed,sim._streamed).ok,"default rebase boundary still rejects unexplained quiescent role loss")
	var owned := state.duplicate(true)
	owned.enemy_attack_instances = [{"source_id":str(owned.entities[0].id)}]
	t.check(not sim._reconcile_rebased_motion(owned,missing,sim._streamed,sim._streamed,[owned.entities[0].id]).ok,"explicit retirement cannot excuse a source that still owns a raw attack")
	t.check(sim.Population.plan(owned).retire.is_empty(),"real population policy never retires a raw attack owner")
	var tick: int = state.active_tick
	var stats: Dictionary = state.stats.duplicate(true)
	var events := F.step(sim,state,Vector2.ZERO)
	var status: Dictionary = sim.step_status()
	t.check(status.ok and state.active_tick == tick+1 and state.world.origin_revision == 1 and state.entities.is_empty(),"normal grabber population retirement and rebase commit instead of rolling back")
	if not status.ok: print("RETIRE_REBASE_STATUS ",status); return
	t.check(status.population.retired == 1 and status.population.retired_entity_ids == [77] and state.stats == stats and F.types(events,"kill").is_empty() and state.enemy_attack_instances.is_empty() and sim.enemy_attack_view(state).attacks.is_empty(),"retired source leaves no reward attack or view record")
	t.check(sim.restore(state,hydrated.deltas).ok,"retired and rebased authoritative state restores")

func _diagonal_cap_roundtrip(t) -> void:
	var f := fixture(t); var sim = f.sim; var state: Dictionary = f.state
	state.player.position = [740.0,384.0]
	var spawn := command([670.2345581054688,385.1234436035156])
	var needed: Dictionary = Helper.requirements(state,[spawn])
	var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,needed.chunks)
	t.check(needed.ok and hydrated.ok and sim.prepare_world(state,hydrated.deltas,[spawn]).ok,"actual diagonal hand fixture prepares")
	F.step(sim,state,Vector2.ZERO,[spawn])
	t.check(state.enemy_attack_instances.size() == 1,"actual diagonal hand acquires a saved reach cap")
	if state.enemy_attack_instances.is_empty(): return
	var first_cap: float = state.entities[0].role_hand_reach
	var first_packet: Dictionary = sim.enemy_attack_view(state)
	t.check(first_cap != floor(first_cap),"diagonal fixture exercises noninteger real_t reach")
	var warm := state.duplicate(true)
	var current := state
	for index in 3:
		var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(current,"",true,true)),hydrated.deltas)
		t.check(restored.get("ok",false) and restored.state == warm and restored.state.entities[0].role_hand_reach == first_cap and restored.attack_view == first_packet,"precise JSON roundtrip preserves the exact first reach and hand packet: "+str(index))
		if not restored.get("ok",false): return
		current = restored.state
