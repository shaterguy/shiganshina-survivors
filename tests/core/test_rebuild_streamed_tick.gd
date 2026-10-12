extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const Disk = preload("res://game/persistence/world_delta_store.gd")
const F = preload("res://tests/core/core_fixture.gd")
class LateHelper:
	extends "res://game/core/streamed_run_world.gd"
	var armed := false
	var cover_calls := 0
	func fresh(): return LateHelper.new(_definitions)
	func cover_query(origin: Vector2,target: Vector2,radius: float,mask: int) -> Dictionary:
		cover_calls += 1
		if armed and cover_calls == 2: return _query_result(failure("world_not_ready"))
		return super.cover_query(origin,target,radius,mask)
func fixture(t,position: Array = [384.0,384.0],late: bool = false) -> Dictionary:
	var provider := City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var sim := Core.new(provider,LateHelper.new(chapter.world_definitions) if late else null)
	var state := sim.new_run(chapter,42,F.run_config())
	state.player.position = position.duplicate()
	var disk := Disk.new("/tmp/c4_tick_%d_%d"%[OS.get_process_id(),Time.get_ticks_usec()])
	var prepared: Dictionary = disk.prepare(state.world.delta_root,[],0)
	var needed := Helper.requirements(state)
	var hydrated: Dictionary = disk.hydrate(state.world.delta_root,needed.chunks)
	var ready := sim.prepare_world(state,hydrated.deltas)
	t.check(prepared.ok and needed.ok and hydrated.ok and ready.ok,"streamed tick fixture is actual Core-valid and disk-hydrated")
	return {"sim":sim,"state":state,"disk":disk,"hydration":hydrated.deltas,"chapter":chapter} if ready.ok else {}
func run(t) -> void:
	var setup := fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	var helper_id: int = sim._streamed.get_instance_id()
	var world_id: int = sim._streamed._world.get_instance_id()
	var source := state.duplicate(true)
	F.step(sim,state,Vector2.RIGHT)
	t.check(state.active_tick == 1 and state.player.position == [386.5,384.0],"actual streamed Core tick advances exactly one fixed step")
	t.check(sim._streamed.get_instance_id() == helper_id and sim._streamed._world.get_instance_id() == world_id,"ordinary city tick reuses helper and prepared geometry")
	if state.active_tick != 1: return
	for tick in 20: F.step(sim,state,Vector2.ZERO)
	t.check(sim._streamed.get_instance_id() == helper_id and sim._streamed._world.get_instance_id() == world_id,"repeated ordinary ticks never regenerate world/helper")
	var fresh := Core.new(City.new())
	var required := Helper.requirements(state)
	var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,required.chunks)
	var restored := fresh.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration.deltas)
	t.check(restored.get("ok",false) and fresh.prepare_world(restored.state,hydration.deltas).ok,"moving city state passes real cold restore/preparation")
	if restored.get("ok",false):
		var replay: Dictionary = restored.state
		for tick in 12:
			var a := F.step(sim,state,Vector2.DOWN)
			var b := F.step(fresh,replay,Vector2.DOWN)
			t.check(a == b and state == replay,"city movement JSON cut replay is exact: "+str(tick))
	var missing := source.duplicate(true)
	missing.player.position = [2200.0,384.0]
	var before := missing.duplicate(true)
	t.check(F.step(sim,missing,Vector2.RIGHT).is_empty() and missing == before,"natural missing coverage leaves clocks/RNG/authority untouched")
	var stale := {"command_id":"old-origin","kind":"spawn_enemy","origin_revision":1,"payload":{"entity_id":"stale","enemy_id":"walker","position":[440,384],"spawned_tick":0}}
	before = state.duplicate(true)
	t.check(F.step(sim,state,Vector2.ZERO,[stale]).is_empty() and state == before,"stale spatial command rejects the whole tick without teleportation")
	_collision(t)
	_late_failure(t)
	_growth(t)
	_projectile_cover(t)
	_physical_cover(t)
	_navigation_replay(t)
	_full_command_ledger(t)
	_behavior_identity(t)
	_body_identity(t)
	_wide_origin_revision(t)
	_clearance_target(t)
func _collision(t) -> void:
	var setup := fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	var props: Dictionary = sim._streamed.props_query(Rect2(0,0,768,768))
	var found := false
	for prop in props.props:
		if prop.collision_mask == 0: continue
		var box: Rect2 = prop.ground_footprint
		var point := Vector2(box.position.x-10,box.get_center().y)
		if not sim._streamed.walkable(point,8).get("walkable",false): continue
		state.player.position = [point.x,point.y]
		var required := Helper.requirements(state)
		var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,required.chunks)
		if not sim.prepare_world(state,hydration.deltas).ok: continue
		found = true
		for tick in 50: F.step(sim,state,Vector2.RIGHT)
		t.check(state.active_tick == 50 and state.player.position[0] <= box.position.x-8+0.001,"actual player movement collides with generated ground footprint")
		t.check(sim.restore(state,hydration.deltas).get("ok",false),"blocked movement remains a valid saved city state")
		break
	t.check(found,"collision fixture found a real generated solid with legal approach")
func _late_failure(t) -> void:
	var setup := fixture(t,[384.0,384.0],true)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.equipment = {"blade_slash":5}
	state.run_config = state.run_config.duplicate()
	state.run_config.prepared_supply = "field_bandage"
	state.player.hp = 20.0
	state.player.xp = 24
	var command := {"command_id":"late:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"late-target","enemy_id":"walker","position":[430,384],"spawned_tick":0}}
	var needed := Helper.requirements(state,[command])
	var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,needed.chunks)
	t.check(sim.prepare_world(state,hydration.deltas,[command]).ok,"late-failure fixture covers command and full target geometry")
	var before := state.duplicate(true)
	sim._streamed.armed = true
	var events := F.step(sim,state,Vector2.RIGHT,[command])
	t.check(sim._streamed.cover_calls == 2,"fault occurs on actual late attack contact after targeting/earlier mutations")
	t.check(events.is_empty() and state == before,"late query failure rolls back movement/cast/cooldown/spawn/ledgers/clocks/RNG atomically")
	sim._streamed.armed = false
	sim._streamed.cover_calls = 0
	events = F.step(sim,state,Vector2.RIGHT,[command])
	t.check(state.active_tick == 1 and state.stats.kills == 1 and not events.is_empty(),"ready retry applies the successful combat tick exactly once")
	t.check(state.supply_used and state.player.hp == 45.0 and not state.upgrade_offer.is_empty() and state.progression_rng_state != before.progression_rng_state,"control retry also proves supply healing and growth RNG/FIFO effects were rolled back")
	t.check(sim.restore(state,hydration.deltas).get("ok",false),"post-retry state passes actual city restore")

func _growth(t) -> void:
	var setup := fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.xp = 24
	F.step(sim,state,Vector2.ZERO)
	t.check(not state.upgrade_offer.is_empty(),"actual city tick materializes a real growth offer")
	if state.upgrade_offer.is_empty(): return
	var chosen := str(state.upgrade_offer.options[0].option_id)
	var result: Dictionary = sim.choose_upgrade(state,state.upgrade_offer.offer_id,chosen)
	t.check(result.get("ok",false),"city growth selection validates using the pinned prepared hydration")
	t.check(sim.restore(state,setup.hydration).get("ok",false),"selected city upgrade passes actual full restore")

func cover_fixture(t) -> Dictionary:
	var setup := fixture(t)
	if setup.is_empty(): return {}
	var sim = setup.sim
	for prop in sim._streamed.props_query(Rect2(0,0,768,768)).props:
		if prop.collision_mask == 0 or not prop.destructible: continue
		var box: Rect2 = prop.ground_footprint
		var left := Vector2(box.position.x-36,box.get_center().y)
		var right := Vector2(box.end.x+36,box.get_center().y)
		if sim._streamed.walkable(left,24).get("walkable",false) and sim._streamed.walkable(right,24).get("walkable",false):
			setup.left = left; setup.right = right; setup.box = box; setup.prop = prop
			return setup
	t.check(false,"cover fixture requires legal opposite approaches to actual destructible geometry")
	return {}
func _projectile_cover(t) -> void:
	var setup := cover_fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.equipment = {"wall_cannon":1}
	var command := {"command_id":"cover:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"cover-target","enemy_id":"walker","position":[470,384],"spawned_tick":0}}
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.projectiles.size() == 1,"projectile cover control uses a real Core cast")
	if state.projectiles.size() != 1: return
	state.player.position = [setup.left.x,setup.left.y]
	state.entities[0].position = [setup.right.x,setup.right.y]
	state.entities[0].locked_origin = state.entities[0].position.duplicate()
	state.projectiles[0].position = [setup.box.position.x-6,setup.box.get_center().y]
	state.projectiles[0].velocity = [480.0,0.0]
	var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state).chunks)
	t.check(sim.prepare_world(state,hydration.deltas).get("ok",false),"arranged in-flight projectile/opposite actor passes actual Core restore")
	var before := state.duplicate(true)
	var events := F.step(sim,state,Vector2.ZERO)
	t.check(state.active_tick == 2 and state.projectiles.is_empty(),"real projectile stops at the first generated cover footprint")
	t.check(state.stats.damage_dealt == 0 and F.types(events,"projectile_impact").size() == 1,"cover prevents damage behind the wall and emits exactly one impact")
	var ruined := before.duplicate(true)
	ruined.world.world_revision = 1
	ruined.world.dirty_chunks = [{"chunk":["0","0"],"props":[{"slot_id":setup.prop.slot_id,"hp":0,"destroyed":true}]}]
	var cleared := Core.new(City.new())
	t.check(cleared.prepare_world(ruined,hydration.deltas).get("ok",false),"arranged ruined-prop candidate prepares through real helper")
	F.step(cleared,ruined,Vector2.ZERO)
	t.check(ruined.active_tick == 2 and ruined.projectiles.size() == 1 and ruined.projectiles[0].position[0] > setup.box.position.x,"same projectile passes the same footprint after verified ruin geometry")
func _physical_cover(t) -> void:
	var setup := cover_fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.position = [setup.left.x,setup.left.y]
	state.equipment = {"odm_dash":5}
	state.passives = {"attack_range":5}
	var command := {"command_id":"physical:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"physical-target","enemy_id":"walker","position":[setup.right.x,setup.right.y],"spawned_tick":0}}
	var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state,[command]).chunks)
	t.check(sim.prepare_world(state,hydration.deltas,[command]).get("ok",false),"physical cover control is fully prepared")
	var events := F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.active_tick == 1 and state.entities.size() == 1,"physical cover fixture actually runs and spawns the opposite target")
	t.check(state.stats.damage_dealt == 0 and state.attack_seq == 0 and F.types(events,"player_attack").is_empty(),"physical target selection cannot acquire a target through generated cover")

func _navigation_replay(t) -> void:
	var setup := cover_fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.position = [setup.left.x,setup.left.y]
	state.player.attack_ready_ticks = {"blade_slash":10000}
	var command := {"command_id":"navigation:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"route-target","enemy_id":"walker","position":[setup.right.x,setup.right.y],"spawned_tick":0}}
	var hydration: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state,[command]).chunks)
	t.check(sim.prepare_world(state,hydration.deltas,[command]).get("ok",false),"obstructed navigation replay starts from full valid coverage")
	F.step(sim,state,Vector2.ZERO,[command])
	for tick in 19: F.step(sim,state,Vector2(0,0.1))
	t.check(state.active_tick == 20 and state.entities.size() == 1,"blocked direct line uses real city navigation without freezing the run")
	if state.active_tick != 20 or state.entities.is_empty(): return
	var cold := Core.new(City.new())
	var restored := cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),hydration.deltas)
	t.check(restored.get("ok",false) and cold.prepare_world(restored.state,hydration.deltas).ok,"warm navigation checkpoint cold-restores with fresh route caches")
	if not restored.get("ok",false): return
	var replay: Dictionary = restored.state
	var start := Time.get_ticks_usec()
	for tick in 40:
		var direction := Vector2(0,0.1 if tick < 20 else -0.1)
		var a := F.step(sim,state,direction)
		var b := F.step(cold,replay,direction)
		t.check(a == b and state == replay,"warm/cold obstructed navigation replay is exact: "+str(tick))
	print("C4B_ROUTE_REPLAY_80_TICKS_USEC "+str(Time.get_ticks_usec()-start))

func _full_command_ledger(t) -> void:
	var setup := fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.attack_ready_ticks = {"blade_slash":10000}
	var command := {"command_id":"ledger:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"ledger-brute","enemy_id":"brute","position":[650,384],"spawned_tick":0}}
	F.step(sim,state,Vector2.ZERO,[command])
	t.check(state.entities.size() == 1 and state.entities[0].action_state == "move","ledger boundary starts with a real moving brute")
	if state.entities.size() != 1: return
	for index in range(state.command_ids_applied.size(),16384): state.command_ids_applied.append("prior:"+str(index))
	state.player.position = [600.0,384.0]
	var hydrated: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state).chunks)
	t.check(sim.prepare_world(state,hydrated.deltas).get("ok",false),"full saved command ledger is a valid boundary state")
	var x: float = state.entities[0].position[0]
	F.step(sim,state,Vector2.ZERO)
	t.check(state.active_tick == 2 and state.entities[0].action_state == "move" and state.entities[0].position[0] < x,"exhausted behavior admission defers only the attack and retains legal movement")
	t.check(sim.restore(state,hydrated.deltas).get("ok",false),"behavior admission refusal cannot leave an orphan windup checkpoint")

func _clearance_target(t) -> void:
	var setup := cover_fixture(t)
	if setup.is_empty(): return
	var sim = setup.sim
	var state: Dictionary = setup.state
	state.player.position = [setup.box.position.x-10,setup.box.get_center().y]
	state.player.attack_ready_ticks = {"blade_slash":10000}
	var command := {"command_id":"clearance:spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"large-clearance","enemy_id":"walker","position":[setup.right.x,setup.right.y],"spawned_tick":0}}
	var hydrated: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state,[command]).chunks)
	t.check(sim.prepare_world(state,hydrated.deltas,[command]).get("ok",false),"radius8 player legitimately stands near a wall")
	F.step(sim,state,Vector2.ZERO,[command])
	var status: Dictionary = sim.step_status()
	t.check(state.active_tick == 1 and status.get("ok",false),"larger enemy's blocked target does not freeze the entire game")
	t.check(status.get("navigation",{}).get("target_adjustments",0) > 0,"enemy clearance target adjustment has explicit diagnostics")
	var measured := false
	for actor in status.get("navigation",{}).get("actors",[]):
		if actor.entity_id == "large-clearance" and actor.reason == "target_clearance_adjusted":
			measured = sim._streamed.walkable(Vector2(actor.legal_target[0],actor.legal_target[1]),18).get("walkable",false)
	t.check(measured,"per-actor diagnostics identify a genuinely legal radius18 target")

func _behavior_identity(t) -> void:
	for mode in ["existing","spawn_collision","long_entity_id"]:
		var setup := fixture(t)
		if setup.is_empty(): return
		var sim = setup.sim
		var state: Dictionary = setup.state
		state.player.attack_ready_ticks = {"blade_slash":10000}
		var actor_id: String = "x".repeat(130) if mode == "long_entity_id" else "identity-brute"
		var behavior_id := "behavior:"+actor_id+":1"
		var spawn := {"command_id":behavior_id if mode == "spawn_collision" else "identity-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":actor_id,"enemy_id":"brute","position":[650,384] if mode == "existing" else [470,384],"spawned_tick":0}}
		F.step(sim,state,Vector2.ZERO,[spawn])
		if mode == "existing":
			state.command_ids_applied.append(behavior_id)
			state.command_ids_applied.sort()
			state.player.position = [600.0,384.0]
			var hydrated: Dictionary = setup.disk.hydrate(state.world.delta_root,Helper.requirements(state).chunks)
			t.check(sim.prepare_world(state,hydrated.deltas).get("ok",false),"claimed future behavior command is a Core-valid control")
			F.step(sim,state,Vector2.ZERO)
		t.check(state.entities.size() == 1 and state.entities[0].action_state == "move" and state.entities[0].pattern_index == 0 and state.telegraphs.is_empty(),"unavailable behavior identity defers before windup mutation: "+mode)
		t.check(sim.restore(state,setup.hydration).get("ok",false),"identity admission refusal preserves a restorable actual tick: "+mode)

func _body_identity(t) -> void:
	for id in ["1","01",1,1.0]:
		var setup := fixture(t)
		if setup.is_empty(): return
		var state: Dictionary = setup.state
		state.player.attack_ready_ticks = {"blade_slash":10000}
		var spawn := {"command_id":"string-body","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":id,"enemy_id":"brute","position":[470,384],"spawned_tick":0}}
		F.step(setup.sim,state,Vector2.ZERO,[spawn])
		t.check(state.entities.size() == 1 and state.telegraphs.size() == 1 and str(state.entities[0].id) != str(state.telegraphs[0].id),"string body and generated hazard identities never collide: "+str(id))
		t.check(setup.sim.restore(state,setup.hydration).get("ok",false),"numeric-looking string body leaves a valid checkpoint: "+str(id))
	var setup := fixture(t)
	if setup.is_empty(): return
	var state: Dictionary = setup.state
	state.drops = [{"id":1,"position":[444.0,384.0],"xp":4}]
	state.next_entity_id = 2
	t.check(setup.sim.restore(state,setup.hydration).get("ok",false),"cross-collection collision starts from an actual valid drop checkpoint")
	var spawn := {"command_id":"drop-collision","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"1","enemy_id":"brute","position":[650,384],"spawned_tick":0}}
	F.step(setup.sim,state,Vector2.ZERO,[spawn])
	t.check(state.entities.is_empty() and setup.sim.restore(state,setup.hydration).get("ok",false),"incoming entity cannot reuse an existing drop identity")
	for id in ["2147483646","2147483647"]:
		var boundary := fixture(t)
		if boundary.is_empty(): return
		var before: Dictionary = boundary.state.duplicate(true)
		spawn.payload.entity_id = id
		var events := F.step(boundary.sim,boundary.state,Vector2.ZERO,[spawn])
		t.check(events.is_empty() and boundary.state == before,"numeric-string incoming high-water exhaustion is atomic: "+id)
	var control := fixture(t)
	if control.is_empty(): return
	spawn.payload.entity_id = "1"
	F.step(control.sim,control.state,Vector2.ZERO,[spawn])
	control.state.next_entity_id = 2
	t.check(control.sim.restore(control.state,control.hydration).get("ok",false),"reserved numeric-string body high-water is a valid control")
	control.state.next_entity_id = 1
	t.check(not control.sim.restore(control.state,control.hydration).get("ok",false),"restore rejects a numeric-string body aliasing the next allocator identity")

func _wide_origin_revision(t) -> void:
	for revision in [2147483648,9007199254740991]:
		var setup := fixture(t)
		if setup.is_empty(): return
		var state: Dictionary = setup.state
		state.player.attack_ready_ticks = {"blade_slash":10000}
		var spawn := {"command_id":"wide-origin","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"wide-origin-brute","enemy_id":"brute","position":[650,384],"spawned_tick":0}}
		F.step(setup.sim,state,Vector2.ZERO,[spawn])
		state.world.origin_revision = revision
		state.player.position = [600.0,384.0]
		t.check(setup.sim.prepare_world(state,setup.hydration).get("ok",false),"full safe-JSON origin revision is valid authoritative world state")
		F.step(setup.sim,state,Vector2.ZERO)
		t.check(state.entities[0].action_state == "windup" and state.telegraphs.size() == 1,"internal spatial command accepts the same world origin counter domain")
		t.check(setup.sim.restore(state,setup.hydration).get("ok",false),"wide origin revision cannot create an orphan admitted attack")
