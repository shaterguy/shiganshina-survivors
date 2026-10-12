extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const C = preload("res://tests/core/core_fixture.gd")
class FaultHelper:
	extends "res://game/core/streamed_run_world.gd"
	var fault := ""
	var next_frame := false
	func fresh():
		var result := FaultHelper.new(_definitions)
		result.fault = fault
		result.next_frame = not fault.is_empty()
		return result
	func sweep(position: Vector2, delta: Vector2, radius: float) -> Dictionary:
		var result: Dictionary = super.sweep(position,delta,radius)
		if not result.get("ok",false) or not next_frame: return result
		if fault == "oversized" and delta.length() > 1.0: result.position += Vector2(0.1,0)
		if fault == "contact_sequence" and delta.length() > 1.0: result.fraction = 0.5; result.hit_prop_id = "review-injected-contact"
		if fault == "blocked" and delta.length() > 0.0 and delta.length() < 0.03125: result.position = position; result.fraction = 0.0; result.hit_prop_id = "review-injected-blocker"
		return result
class NoRebaseCore:
	extends "res://game/core/run_simulation.gd"
	func _step_streamed(state: Dictionary, move: Vector2, commands: Array[Dictionary]) -> Array[Dictionary]:
		var ready: Dictionary = _streamed.begin_query_batch(state,commands)
		if not ready.get("ok",false): _last_step_status = ready; return []
		var candidate := _tick_candidate(state)
		_tick_navigation = {"target_adjustments":0,"target_waits":0,"route_queries":0,"deferred_attacks":0,"actors":[]}
		var events := _step_running(candidate,move,commands)
		var status: Dictionary = _streamed.query_status()
		if not status.get("ok",false): _last_step_status = status; return []
		state.clear(); state.merge(candidate,true); _last_step_status = {"ok":true}
		return events
func run(t) -> void:
	var late := _pending("boss_charger",false,false)
	t.check(late.get("ok",false),"stage1c pending late-charge fixture is valid")
	if late.get("ok",false):
		_replay_and_invariants(t,late,"late charge")
		_faults(t,late)
	var combat := _pending("boss_charger",false,false)
	t.check(combat.get("ok",false),"stage1c damage and XP fixture is valid")
	if combat.get("ok",false):
		combat.state.player.invulnerable_until = combat.state.active_tick
		combat.state.drops = [{"id":combat.state.next_entity_id,"position":combat.state.player.position.duplicate(),"xp":1}]
		combat.state.next_entity_id += 1
		t.check(combat.core.prepare_world(combat.state,combat.hydration).get("ok",false),"stage1c damage and XP arrangement passes full restore")
		_replay_and_invariants(t,combat,"damage and XP on rebase")
	var negative := _pending("boss_charger",true,false)
	t.check(negative.get("ok",false),"stage1c negative late-charge fixture is valid")
	if negative.get("ok",false): _replay_and_invariants(t,negative,"negative late charge")
	var grab := _pending("grabber",true,false)
	t.check(grab.get("ok",false),"stage1c late-grab fixture is valid")
	if grab.get("ok",false): _replay_and_invariants(t,grab,"negative late grab")
	var leap := _pending("boss_leaper",true,false)
	t.check(leap.get("ok",false),"stage1c airborne negative-rebase fixture is valid")
	if leap.get("ok",false): _replay_and_invariants(t,leap,"negative airborne leap")
	var wall := _pending("boss_charger",false,true)
	t.check(wall.get("ok",false),"stage1c real wall-contact fixture is valid: "+str(wall.get("reason","")))
	if wall.get("ok",false): _replay_and_invariants(t,wall,"real wall contact",true)
func _pending(enemy: String, negative: bool, wall: bool) -> Dictionary:
	var provider = City.new()
	var chapter: Dictionary = provider.load_chapter("chapter_01_shiganshina").chapter
	var core = Core.new(provider,FaultHelper.new(chapter.world_definitions))
	var state: Dictionary = core.new_run(chapter,42,C.run_config())
	state.player.position = [1.0,384.0] if negative else [766.0,384.0]
	state.player.attack_ready_ticks = {"blade_slash":60000}
	if enemy == "boss_charger": state.active_tick = 17999; state.survival_tick = 17999
	if enemy == "boss_leaper": state.active_tick = 53999; state.survival_tick = 53999
	var hydration := F.hydration(H.requirements(state))
	if not core.prepare_world(state,hydration).get("ok",false): return {"ok":false,"reason":"initial prepare"}
	var origin := Vector2(80.12345123291016,387.9876403808594) if negative else Vector2(655.1234741210938,387.9876403808594)
	if wall:
		origin = Vector2(INF,INF)
		var player := Vector2(state.player.position[0],state.player.position[1])
		for y in range(64,705,32):
			for x in range(384,1089,32):
				var point := Vector2(x,y)
				if point.distance_to(player) > 410 or point.distance_to(player) < 80: continue
				if not core._streamed.walkable(point,28).get("walkable",false): continue
				var sweep: Dictionary = core._streamed.sweep(point,point.direction_to(player)*300.0,28)
				if sweep.get("ok",false) and sweep.fraction > 0.05 and sweep.fraction < 0.95:
					origin = point
					break
			if is_finite(origin.x): break
		if not is_finite(origin.x): return {"ok":false,"reason":"no real wall-charge origin"}
	var command := {"command_id":"motion-contract-spawn","kind":"spawn_enemy","origin_revision":0,"payload":{"entity_id":"motion-contract-actor","enemy_id":enemy,"position":[origin.x,origin.y],"spawned_tick":0}}
	if enemy == "boss_charger": command.kind = "spawn_boss"; command.payload.erase("spawned_tick"); command.payload.boss_id = "ch01_b05"; command.payload.scheduled_tick = 18000
	if enemy == "boss_leaper": command.kind = "spawn_boss"; command.payload.erase("spawned_tick"); command.payload.boss_id = "ch01_b15"; command.payload.scheduled_tick = 54000
	hydration = F.hydration(H.requirements(state,[command]))
	if not core.prepare_world(state,hydration,[command]).get("ok",false): return {"ok":false,"reason":"command prepare"}
	C.step(core,state,Vector2.ZERO,[command])
	if state.entities.size() != 1: return {"ok":false,"reason":"spawn"}
	var move_at := 120 if enemy == "boss_charger" else (90 if enemy == "boss_leaper" else 72)
	for i in move_at: C.step(core,state,Vector2.ZERO)
	C.step(core,state,Vector2.LEFT if negative else Vector2.RIGHT)
	if not core.step_status().get("ok",false): return {"ok":false,"reason":"warmup","status":core.step_status()}
	var normalized := H.Address.normalize(state.world.origin_chunk,Vector2(state.player.position[0],state.player.position[1]))
	if normalized.offset == Vector2.ZERO: return {"ok":false,"reason":"did not cross boundary"}
	var restored: Dictionary = core.restore(state,hydration)
	if not restored.get("ok",false): return {"ok":false,"reason":"pre-rebase restore","status":restored}
	return {"ok":true,"core":core,"state":state,"hydration":hydration,"chapter":chapter}
func _replay_and_invariants(t, f: Dictionary, label: String, require_wall: bool = false) -> void:
	var state: Dictionary = f.state
	var source := state.duplicate(true)
	var source_helper = f.core._streamed
	var proposed := H.rebase_proposal(source)
	t.check(proposed.get("ok",false),"stage1c private rebase proposal: "+label)
	if not proposed.get("ok",false): return
	f.core._canonicalize_saved_vectors(proposed.state)
	var candidate_before: Dictionary = proposed.state.duplicate(true)
	var next = source_helper.fresh()
	t.check(next.prepare(proposed.state,f.hydration).get("ok",false),"stage1c candidate real geometry prepares: "+label)
	var original_pose: Dictionary = f.core._action_motion_pose(source,source.entities[0],Core.Behaviors.profile(source.entities[0]),source_helper,true)
	var reconciled: Dictionary = f.core._reconcile_rebased_motion(source,proposed.state,source_helper,next)
	t.check(reconciled.get("ok",false),"stage1c bounded motion reconstruction succeeds: "+label+" "+str(reconciled))
	if not reconciled.get("ok",false): return
	var stripped: Dictionary = proposed.state.duplicate(true)
	for i in stripped.entities.size():
		stripped.entities[i].position = candidate_before.entities[i].position
		stripped.entities[i].velocity = candidate_before.entities[i].velocity
	t.check(stripped == candidate_before and state == source,"stage1c reconstruction changes only private current position/velocity: "+label)
	var next_pose: Dictionary = f.core._action_motion_pose(proposed.state,proposed.state.entities[0],Core.Behaviors.profile(proposed.state.entities[0]),next,true)
	t.check(original_pose.contacts == next_pose.contacts,"stage1c exact step/prop contact sequence preserved: "+label)
	if require_wall: t.check(not original_pose.contacts.is_empty(),"stage1c wall test has genuine generated-prop contacts")
	var provider = City.new()
	var control = NoRebaseCore.new(provider)
	var old_frame: Dictionary = source.duplicate(true)
	t.check(control.prepare_world(old_frame,f.hydration).get("ok",false),"stage1c independent old-frame control prepares: "+label)
	var expected_events := C.step(control,old_frame,Vector2.ZERO)
	var events := C.step(f.core,state,Vector2.ZERO)
	var status: Dictionary = f.core.step_status()
	t.check(status.get("ok",false) and state.world.origin_revision == source.world.origin_revision+1,"stage1c full tick commits exactly one rebase: "+label)
	t.check(events == expected_events,"stage1c damage/event payloads and IDs agree with old-frame control: "+label)
	if label == "damage and XP on rebase":
		t.check(not C.types(events,"damage").is_empty() and not C.types(events,"xp_gained").is_empty(),"stage1c rebase tick truly exercises damage and XP event allocation")
	for field in ["active_tick","survival_tick","event_seq","next_entity_id","attack_seq","offer_seq","view_revision","stats","boss_ids_fired","reward_ids_claimed","command_ids_applied","pending_offers"]:
		t.check(state[field] == old_frame[field],"stage1c clocks/rewards/IDs invariant: "+label+"/"+field)
	for field in ["hp","xp","level","invulnerable_until"]: t.check(state.player[field] == old_frame.player[field],"stage1c player combat outcome invariant: "+label+"/"+field)
	for field in ["id","hp","action_state","action_started_tick","action_ends_tick","next_action_tick","pattern_index","attack_kind"]: t.check(state.entities[0][field] == old_frame.entities[0][field],"stage1c actor identity/combat clocks invariant: "+label+"/"+field)
	var restored: Dictionary = f.core.restore(JSON.parse_string(JSON.stringify(state,"",true,true)),f.hydration)
	t.check(restored.get("ok",false) and restored.get("state",{}) == state,"stage1c corrected checkpoint is canonical and cold-restorable: "+label)
	if not restored.get("ok",false): return
	var cold = Core.new(City.new())
	t.check(cold.prepare_world(restored.state,f.hydration).get("ok",false),"stage1c independent cold helper prepares: "+label)
	for i in 12:
		var a := C.step(f.core,state,Vector2.ZERO)
		var b := C.step(cold,restored.state,Vector2.ZERO)
		t.check(f.core.step_status().get("ok",false) and cold.step_status().get("ok",false) and a == b and state == restored.state,"stage1c 12-tick warm/cold replay: "+label)
	print("STAGE1C_MOTION_CONTRACT ",JSON.stringify({"case":label,"contacts":original_pose.contacts,"rebase_status":status},"",true,true))
func _faults(t, source_fixture: Dictionary) -> void:
	# Recreate the pending frame because the replay test has already advanced its input.
	for fault in ["oversized","blocked","contact_sequence","invalid_source"]:
		var f := _pending("boss_charger",false,false)
		t.check(f.get("ok",false),"stage1c injected rollback fixture prepares: "+fault)
		if not f.get("ok",false): continue
		var state: Dictionary = f.state
		var helper = f.core._streamed
		if fault == "invalid_source": state.entities[0].position[0] += 0.25
		else: helper.fault = fault
		var before: Dictionary = state.duplicate(true)
		var view: Dictionary = f.core.world_render_view(state)
		var events := C.step(f.core,state,Vector2.ZERO)
		var status: Dictionary = f.core.step_status()
		var expected: String = {"oversized":"rebase_motion_discontinuity","blocked":"rebase_motion_contact_changed","contact_sequence":"rebase_motion_discontinuity","invalid_source":"invalid_core_state"}[fault]
		t.check(status.get("error_code") == expected and events.is_empty(),"stage1c injected hazard is refused: "+fault+" "+str(status))
		t.check(state == before and f.core._streamed == helper and f.core.world_render_view(state) == view,"stage1c refused reconstruction preserves authority/helper/geometry: "+fault)
		print("STAGE1C_FAULT_CONTRACT ",JSON.stringify({"fault":fault,"status":status,"unchanged":state == before,"same_helper":f.core._streamed == helper},"",true,true))
