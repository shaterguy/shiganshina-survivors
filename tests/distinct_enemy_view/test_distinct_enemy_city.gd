extends RefCounted
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core_world/test_live_grabber_transaction.gd")
const View = preload("res://game/presentation/world_view.gd")
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
func run(t) -> void:
	for role in ["grabber","quadruped","stone_thrower"]: _rebase(t,role)
	_destroy_blocker(t)
func _rebase(t,role: String) -> void:
	var f := G.new().fixture(t)
	var state: Dictionary = f.state
	var command: Dictionary = G.new().command()
	command.payload.enemy_id = role
	F.step(f.sim,state,Vector2.ZERO,[command])
	t.check(state.enemy_attack_instances.size() == 1,"city admits view rebase fixture: "+role)
	if state.enemy_attack_instances.is_empty(): return
	var active := int(state.enemy_attack_instances[0].active_from_tick)+5
	while int(state.active_tick) < active: F.step(f.sim,state,Vector2.ZERO)
	var view = View.new(); view.load_manifest()
	t.check(view.present_city(state.duplicate(true),_terrain(f.sim,state)).ok,"real city terrain installs for "+role)
	var old: Dictionary = f.sim.enemy_attack_view(state)
	t.check(view.present_enemy_attacks(old).ok,"actual city packet installs before rebase: "+role)
	var shifted := state.duplicate(true)
	shifted.world.origin_chunk = ["-1","0"]
	shifted.player.position[0] += 768.0
	for actor in shifted.entities:
		for key in ["position","locked_origin","locked_target"]: actor[key][0] += 768.0
	for attack in shifted.enemy_attack_instances:
		for key in ["locked_origin","locked_target"]: attack[key][0] += 768.0
	var hydrated: Dictionary = f.disk.hydrate(shifted.world.delta_root,Helper.requirements(shifted).chunks)
	var fresh := Core.new(City.new())
	var restored: Dictionary = fresh.restore(JSON.parse_string(JSON.stringify(shifted,"",true,true)),hydrated.deltas)
	t.check(restored.get("ok",false),"actual translated role restores: "+role)
	if not restored.get("ok",false): view.free(); return
	shifted = restored.state
	t.check(fresh.prepare_world(shifted,hydrated.deltas).ok,"cold translated city prepares")
	F.step(fresh,shifted,Vector2.ZERO)
	F.step(f.sim,state,Vector2.ZERO)
	t.check(shifted.world.origin_revision == 1 and fresh.step_status().ok,"actual Core origin rebase commits")
	t.check(view.present_city(shifted.duplicate(true),_terrain(fresh,shifted)).ok and view.enemy_attack_commands().is_empty(),"actual new city snapshot clears previous role commands")
	t.check(not view.present_enemy_attacks(old).ok and view.enemy_attack_commands().is_empty(),"real rebase rejects old-coordinate role packet")
	var current: Dictionary = fresh.enemy_attack_view(shifted)
	t.check(view.present_enemy_attacks(current).ok and view._enemy_attack_packet == current and current.attacks == f.sim.enemy_attack_view(state).attacks,"rebased and uninterrupted actual Core role packet agree: "+role)
	t.check(not view.present_city(shifted,{}).ok and view.enemy_attack_commands().is_empty(),"terrain refusal clears all role commands")
	view.free()
func _destroy_blocker(t) -> void:
	var f := G.new().fixture(t)
	var state: Dictionary = f.state
	var sim = f.sim
	var chosen := {}; var origin := Vector2.ZERO; var target := Vector2.ZERO
	for prop in sim._streamed.props_query(Rect2(0,0,768,768)).props:
		if not prop.destructible: continue
		var box: Rect2 = prop.ground_footprint
		origin = Vector2(box.position.x-90,box.get_center().y)
		target = origin+Vector2(60,0)
		if not sim._streamed.walkable(origin,24).get("walkable",false) or not sim._streamed.walkable(target,8).get("walkable",false): continue
		var sweep: Dictionary = sim._streamed.sweep(origin,Vector2(324,0),7)
		if sweep.ok and sweep.fraction < 1.0: chosen = prop; break
	t.check(not chosen.is_empty(),"actual destructible rock blocker is found")
	if chosen.is_empty(): return
	state.player.position = [target.x,target.y]
	var command: Dictionary = G.new().command([origin.x,origin.y]); command.payload.enemy_id = "stone_thrower"
	command.origin_revision = state.world.origin_revision
	var origin_address: Dictionary = Helper.Address.normalize(state.world.origin_chunk,origin)
	var prop_chunk: Array = [str(chosen.prop_id).get_slice(":",2),str(chosen.prop_id).get_slice(":",3)]
	t.check(origin_address.get("ok",false) and Helper.Address.parse(prop_chunk).get("ok",false),"rock fixture preserves canonical source and actual blocker addresses")
	if not origin_address.get("ok",false) or not Helper.Address.parse(prop_chunk).get("ok",false): return
	var needed: Dictionary = Helper.requirements(state,[command])
	t.check(needed.get("ok",false),"moved rock fixture computes public command-aware hydration requirements")
	if not needed.get("ok",false): return
	var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,needed.chunks)
	t.check(hydrated.get("ok",false),"moved rock fixture hydrates all actual required chunks from the same disk root")
	if not hydrated.get("ok",false): return
	f.hydration = hydrated.deltas
	var missing: Array = []
	for chunk in needed.get("chunks",[]):
		var key: String = str(chunk[0])+","+str(chunk[1])
		if not f.hydration.has(key): missing.append(key)
	var frozen: PackedByteArray = var_to_bytes(state)
	var prepared: Dictionary = sim.prepare_world(state,f.hydration,[command])
	print("ROCK_FIXTURE_PREPARE_DIAGNOSTIC ",JSON.stringify({"prop_id":chosen.prop_id,"slot_id":chosen.slot_id,"origin":[origin.x,origin.y],"target":[target.x,target.y],"needed":needed,"hydration_keys":f.hydration.keys(),"missing_hydration_keys":missing,"prepare_result":prepared},"",true,true))
	t.check(prepared.ok,"actual clipped rock fixture prepares")
	t.check(var_to_bytes(state) == frozen,"Core preparation leaves caller positions and origin unchanged before the real tick")
	var before_origin: Dictionary = {"chunk":state.world.origin_chunk.duplicate(),"revision":state.world.origin_revision,"player":state.player.position.duplicate(),"command_origin":command.payload.position.duplicate(),"command_revision":command.origin_revision}
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.enemy_attack_instances.size() == 1,"actual clipped rock attack is admitted")
	if state.enemy_attack_instances.is_empty(): return
	var current_origin: Dictionary = Helper.Address.relative(origin_address.chunk,origin_address.local,state.world.origin_chunk)
	var expected_revision: int = int(before_origin.revision)+(0 if Vector2(needed.offset[0],needed.offset[1]) == Vector2.ZERO else 1)
	t.check(sim.step_status().get("ok",false) and current_origin.get("ok",false) and state.world.origin_chunk == needed.origin_chunk and state.world.origin_revision == expected_revision and Vector2(state.enemy_attack_instances[0].locked_origin[0],state.enemy_attack_instances[0].locked_origin[1]) == current_origin.local,"actual Core tick rebases the rock command once into its committed origin")
	print("ROCK_FIXTURE_REBASE_DIAGNOSTIC ",JSON.stringify({"before":before_origin,"after":{"chunk":state.world.origin_chunk,"revision":state.world.origin_revision,"player":state.player.position,"locked_origin":state.enemy_attack_instances[0].locked_origin},"expected_locked_origin":[current_origin.local.x,current_origin.local.y],"expected_revision":expected_revision,"prop_chunk":prop_chunk,"prop_id":chosen.prop_id},"",true,true))
	var attack: Dictionary = state.enemy_attack_instances[0].duplicate(true)
	var blocked := false
	while int(state.active_tick) < int(attack.attack_ends_tick)-2:
		F.step(sim,state,Vector2.ZERO)
		var packet: Dictionary = sim.enemy_attack_view(state)
		if packet.attacks[0].projectile_pose.blocked and packet.attacks[0].damage_geometry.is_empty(): blocked = true; break
	t.check(blocked,"real rock expires before destroying actual blocker")
	if not blocked: return
	state.world = state.world.duplicate(true)
	state.world.world_revision += 1
	state.world.dirty_chunks = [{"chunk":prop_chunk,"props":[{"slot_id":chosen.slot_id,"hp":0,"destroyed":true}]}]
	needed = Helper.requirements(state)
	hydrated = f.disk.hydrate(state.world.delta_root,needed.get("chunks",[]))
	t.check(needed.get("ok",false) and hydrated.get("ok",false),"actual blocker destruction retains complete current-origin hydration")
	if not needed.get("ok",false) or not hydrated.get("ok",false): return
	f.hydration = hydrated.deltas
	t.check(sim.prepare_world(state,f.hydration).ok,"actual wall destruction re-prepares expired rock")
	var destroyed: Array = []
	for chunk in sim.world_render_view(state).get("chunks",[]):
		for prop in chunk.props:
			if prop.prop_id == chosen.prop_id: destroyed.append(prop)
	t.check(destroyed.size() == 1 and destroyed[0].destroyed,"destruction changes the exact actual blocker rather than a same-slot prop in another chunk")
	var view = View.new(); view.load_manifest()
	while int(state.active_tick) < int(attack.attack_ends_tick):
		F.step(sim,state,Vector2.ZERO)
		view.present_city(state.duplicate(true),_terrain(sim,state))
		var packet: Dictionary = sim.enemy_attack_view(state)
		t.check(view.present_enemy_attacks(packet).ok,"post-destruction actual packet is accepted")
		t.check(view.enemy_attack_commands().is_empty() and not packet.attacks[0].projectile_pose.visible and packet.attacks[0].damage_geometry.is_empty(),"destroyed wall never resurrects stopped rock or damage footprint")
	view.free()

# Match Controller's derived terrain decoration; no geometry is fabricated.
func _terrain(sim, state: Dictionary) -> Dictionary:
	var terrain: Dictionary = sim.world_render_view(state)
	terrain.world_revision = sim.world_status().get("world_revision",state.world.world_revision)
	return terrain
