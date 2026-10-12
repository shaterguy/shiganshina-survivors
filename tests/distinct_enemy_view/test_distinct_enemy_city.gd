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
	t.check(sim.prepare_world(state,f.hydration).ok,"actual clipped rock fixture prepares")
	var command: Dictionary = G.new().command([origin.x,origin.y]); command.payload.enemy_id = "stone_thrower"
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.enemy_attack_instances.size() == 1,"actual clipped rock attack is admitted")
	if state.enemy_attack_instances.is_empty(): return
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
	state.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":chosen.slot_id,"hp":0,"destroyed":true}]}]
	t.check(sim.prepare_world(state,f.hydration).ok,"actual wall destruction re-prepares expired rock")
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
