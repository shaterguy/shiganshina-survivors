extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
const G = preload("res://tests/core_world/test_live_grabber_transaction.gd")
class UncoveredCore:
	extends "res://game/core/run_simulation.gd"
	var force_uncovered := false
	func _regenerate(state: Dictionary) -> void:
		super._regenerate(state)
		if force_uncovered:
			# A genuine out-of-residency query, never a fake geometry response.
			_role_query(state).sweep(_vec(state.player.position),Vector2(8000,0),22)
func run(t) -> void:
	var cases := [
		{"name":"right","point":Vector2(640,0),"move":Vector2.RIGHT,"origin":Vector2(470,0)},
		{"name":"left","point":Vector2(128,0),"move":Vector2.LEFT,"origin":Vector2(298,0)},
		{"name":"down","point":Vector2(0,640),"move":Vector2.DOWN,"origin":Vector2(0,470)},
		{"name":"up","point":Vector2(0,128),"move":Vector2.UP,"origin":Vector2(0,298)},
		{"name":"down_right","point":Vector2(640,-128),"move":Vector2(1,1).normalized(),"origin":Vector2(470,-128)},
		{"name":"down_left","point":Vector2(128,-128),"move":Vector2(-1,1).normalized(),"origin":Vector2(298,-128)},
		{"name":"up_right","point":Vector2(640,128),"move":Vector2(1,-1).normalized(),"origin":Vector2(470,128)},
		{"name":"up_left","point":Vector2(128,128),"move":Vector2(-1,-1).normalized(),"origin":Vector2(298,128)}]
	for item in cases:
		for before_tick in [0,1,61,77]:
			_cross(t,item,before_tick)
	_real_missing_rollback(t)
func _cross(t, item: Dictionary, before_tick: int) -> void:
	# Authored seed42 city geometry; no fake/empty world or cleared props.
	var f := G.new().fixture(t)
	var sim = f.sim
	var state: Dictionary = f.state
	state.player.position = [item.point.x,item.point.y]
	var command: Dictionary = G.new().command([item.origin.x,item.origin.y])
	var needed := H.requirements(state,[command])
	var hydrated: Dictionary = f.disk.hydrate(state.world.delta_root,needed.chunks)
	var prepared: Dictionary = sim.prepare_world(state,hydrated.deltas,[command])
	var label: String = item.name+" before_tick="+str(before_tick)
	t.check(prepared.ok,"real boundary lane prepares "+label)
	if not prepared.ok: return
	t.check(sim._streamed.walkable(item.point,8).walkable and sim._streamed.walkable(item.origin,22).walkable,"player and hand origin are legal in actual city "+label)
	var commands: Array[Dictionary] = [command]
	if before_tick > 0:
		F.step(sim,state,Vector2.ZERO,commands)
		t.check(state.enemy_attack_instances.size() == 1,"boundary fixture begins owned grabber attack "+label)
		if state.enemy_attack_instances.size() != 1: print("BOUNDARY_ADMISSION ",label," ",sim.step_status()); return
		commands = []
		while state.active_tick < before_tick:
			F.step(sim,state,Vector2.ZERO)
			if not sim.step_status().ok: t.check(false,"stationary setup advances "+label); return
	var pre_required: Dictionary = H.requirements(state,commands)
	var old_player: Vector2 = Vector2(state.player.position[0],state.player.position[1])
	var previous: Dictionary = state.duplicate(true)
	var events: Array = F.step(sim,state,item.move,commands)
	var result: Dictionary = sim.step_status()
	t.check(result.get("ok",false) and state.active_tick == before_tick+1,"same prepared tick crosses view boundary "+label)
	if not result.get("ok",false): print("BOUNDARY_REFUSED ",label," ",result); return
	var now := Vector2(state.player.position[0],state.player.position[1])
	var same_origin: Dictionary = H.Address.relative(state.world.origin_chunk,now,previous.world.origin_chunk)
	t.check(same_origin.ok and same_origin.local.distance_to(old_player+item.move*2.5) < 0.0002,"input really crosses specified face(s), unblocked by actual city "+label)
	var missing_after: Dictionary = sim._streamed.readiness(state)
	t.check(not missing_after.ok and not missing_after.missing_delta_keys.is_empty(),"movement expands the next view window rather than receiving padded preparation "+label)
	var query = sim._role_tick_query
	t.check(query != null and query.status().ok and query.status().queries.walkable_calls > 0,"real grabber query consumes original prepared identity "+label)
	if before_tick == 0: t.check(command.command_id in state.command_ids_applied and state.enemy_attack_instances.size() == 1,"new grabber command is applied before query binding "+label)
	else: t.check(state.enemy_attack_instances[0].attack_id == previous.enemy_attack_instances[0].attack_id and state.entities[0].role_hand_reach == previous.entities[0].role_hand_reach,"ongoing hand retains exact owner cap and attack identity "+label)
	# Rebuild from persisted JSON with exact post-move real hydration. Its
	# derived sample must agree, including active and harmless recovery phases.
	var next_hydration: Dictionary = f.disk.hydrate(state.world.delta_root,H.requirements(state).chunks)
	var cold := Core.new(City.new())
	var restored: Dictionary = cold.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),next_hydration.deltas)
	t.check(restored.get("ok",false) and restored.state == state and restored.attack_view == sim.enemy_attack_view(state),"cold restore preserves boundary state and complete attack packet "+label)
	print("CHUNK_MATRIX "+JSON.stringify({"case":item.name,"before_tick":before_tick,"after_tick":state.active_tick,"input":[item.move.x,item.move.y],"pre_chunks":pre_required.chunks.size(),"origin_before":previous.world.origin_chunk,"origin_after":state.world.origin_chunk,"missing_after":missing_after.missing_delta_keys,"query":query.status().queries,"events":events.size()},"",true,true))
	# Missing actual query geometry remains a sticky failure on the bound query.
	var missing: Dictionary = query.sweep(now,Vector2(8000,0),22)
	t.check(not missing.ok and missing.error_code == "world_not_ready" and not query.walkable(now,8).ok,"real out-of-coverage sweep still fails and stays failed "+label)

func _real_missing_rollback(t) -> void:
	var f := G.new().fixture(t)
	var sim := UncoveredCore.new(City.new())
	var state: Dictionary = f.state
	t.check(sim.prepare_world(state,f.hydration).ok,"real late-query transaction prepares")
	F.step(sim,state,Vector2.ZERO,[G.new().command()])
	while state.active_tick < 69:
		F.step(sim,state,Vector2.ZERO)
		if not sim.step_status().ok: t.check(false,"real late-query attack reaches hit tick"); return
	var before: Dictionary = state.duplicate(true)
	var packet: Dictionary = sim.enemy_attack_view(state)
	sim.force_uncovered = true
	var events: Array = F.step(sim,state,Vector2.ZERO)
	t.check(events.is_empty() and state == before and sim.step_status().get("error_code") == "world_not_ready","actual uncovered query rolls tick and damage ledger back atomically")
	t.check(sim.enemy_attack_view(state) == packet and not sim._role_tick_query.status().ok,"real query failure keeps old presentation and sticky bound failure")
	sim.force_uncovered = false
	t.check(sim.prepare_world(state,f.hydration).ok,"fresh real preparation resets refused query only at Core boundary")
	events = F.step(sim,state,Vector2.ZERO)
	t.check(state.active_tick == 70 and F.types(events,"damage").size() == 1 and state.enemy_attack_instances[0].hit_target_ids == ["player"],"same real input retry delivers the rolled-back hit exactly once")
