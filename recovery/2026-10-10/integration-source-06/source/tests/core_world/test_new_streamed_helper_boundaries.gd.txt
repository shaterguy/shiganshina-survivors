extends RefCounted
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const Store = preload("res://game/persistence/world_delta_store.gd")
const Adapter = preload("res://game/app/world_checkpoint_adapter.gd")
func run(t) -> void:
	_json_round_trip(t)
	_isolated_cache_and_query_latch(t)
	_hydrated_delta_merge(t)
	_hostile_packets(t)
	_real_pages(t)
	_structure_admission(t)
	_physical_seams(t)
func _json_round_trip(t) -> void:
	var h = H.new(F.definitions())
	var state := F.state(h)
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(state))
	t.check(H.validate_world(roundtrip).ok,"integral JSON floats are accepted in explicit world counters")
	state.phase = "evacuation"; state.final_started_tick = 108000; state.active_tick = 108000
	h.prepare(state,F.hydration(H.requirements(state)))
	var passage: Dictionary = h.passage_proposal(state); state.world = passage.world
	var command := {"command_id":"dock:json","kind":"dock_transition","origin_revision":0,"payload":{"passage_id":state.world.evacuation.passage_id}}
	var dock: Dictionary = h.dock_transition_proposal(state,command,F.dock())
	state.world = dock.candidate_world; state.player.position = [0,0]
	roundtrip = JSON.parse_string(JSON.stringify(state))
	t.check(H.validate_world(roundtrip).ok,"real JSON round-trip preserves valid dock escape rectangle")
	t.check(h.prepare(roundtrip,{}).ok,"restored dock does not hydrate distant retired city chunks")
	var malformed := state.duplicate(true); malformed.world.scene_id = "city"
	t.check(not H.validate_world(malformed).ok,"dock stage cannot contradict city scene identity")
func _isolated_cache_and_query_latch(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	h.prepare(state,F.hydration(H.requirements(state)))
	var before: Dictionary = h.render_view(state)
	var validation = h.fresh(); var candidate := state.duplicate(true)
	candidate.world.origin_chunk = ["9007199254740993","-123"]
	t.check(validation.prepare(candidate,F.hydration(H.requirements(candidate))).ok,"separate candidate validation prepares far-origin city")
	t.check(h.matches(state) and h.render_view(state) == before,"validation B cannot alter live geometry/origin A")
	t.check(h.begin_query_batch(state).ok,"query batch starts only against ready matching state")
	var late: Dictionary = h.cover_query(Vector2(384,384),Vector2(8000,384),0,8)
	t.check(not late.ok and h.query_status().get("error_code") == "world_not_ready","late cover failure is latched for Core tick rollback")
	h.move(Vector2(384,384),Vector2(2,0),8)
	t.check(not h.query_status().ok,"later successful query cannot clear earlier tick failure")
	t.check(h.begin_query_batch(state).ok and h.query_status().ok,"explicit new ready batch resets query failure")
	var mutated := h.render_view(state); mutated.chunks.clear()
	t.check(h.render_view(state) == before,"render view cannot mutate derived world cache")
func _hydrated_delta_merge(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	var required := H.requirements(state); var hydration := F.hydration(required)
	h.prepare(state,hydration)
	var destructible := []
	for chunk in h.render_view(state).chunks:
		if chunk.chunk == ["0","0"]:
			for prop in chunk.props:
				if prop.destructible: destructible.append(prop)
	t.check(destructible.size() >= 2,"merge fixture has two independent destructible buildings")
	if destructible.size() < 2: return
	hydration["0,0"] = [{"slot_id":destructible[0].slot_id,"hp":1,"destroyed":false}]
	h.prepare(state,hydration)
	var target: Dictionary = destructible[1]
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"structure:merge","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":0,"expires_tick":0,"structure_damage":1}
	var contact := {"prop_id":target.prop_id,"reached":true,"tick":0,"fraction":1.0}
	var result: Dictionary = h.destruction_proposal(state,attack,contact)
	t.check(result.ok and result.world.dirty_chunks[0].props.size() == 2,"new dirty record retains earlier hydrated prop damage in same chunk")
	if result.ok:
		var retained := false
		for prop in result.world.dirty_chunks[0].props:
			if prop.slot_id == destructible[0].slot_id: retained = prop.hp == 1 and not prop.destroyed
		t.check(retained,"persistent chunk replacement cannot resurrect earlier damaged building")
func _hostile_packets(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	state.phase = "evacuation"; state.final_started_tick = 0; state.active_tick = 0
	h.prepare(state,F.hydration(H.requirements(state)))
	var passage: Dictionary = h.passage_proposal(state); state.world = passage.world
	var premature := state.duplicate(true); premature.phase = "survival"
	t.check(not H.validate_world(premature).ok,"persistent passage cannot exist before evacuation phase")
	var bad_time := state.duplicate(true); bad_time.final_started_tick = 1
	t.check(not H.validate_world(bad_time).ok,"passage selection cannot precede final threat start")
	var command := {"command_id":"dock:hostile","kind":"dock_transition","origin_revision":0,"payload":{"passage_id":state.world.evacuation.passage_id}}
	var bad := F.dock(); bad.scene_id = "unknown_scene"
	t.check(not h.dock_transition_proposal(state,command,bad).ok,"unknown dock scene definition cannot produce invalid candidate authority")
	bad = F.dock(); bad.geometry = []
	t.check(not h.dock_transition_proposal(state,command,bad).ok,"malformed dock definition fails before typed pure boundary")
	var abandoned := state.duplicate(true); abandoned.phase = "abandoned"; abandoned.world.stage = "dock"
	t.check(not H.escape_status(abandoned,F.dock()).get("win",false),"invalid abandoned world cannot accidentally win")
func _real_pages(t) -> void:
	var path := "user://new-streamed-helper-pages-"+str(Time.get_ticks_usec())
	var store = Store.new(path)
	var h = H.new(F.definitions()); var state := F.state(h)
	var hydrate := F.hydration(H.requirements(state)); h.prepare(state,hydrate)
	var target := {}
	for chunk in h.render_view(state).chunks:
		if chunk.chunk == ["0","0"]:
			for prop in chunk.props:
				if prop.destructible: target = prop; break
	if target.is_empty(): t.check(false,"disk fixture finds building"); return
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"structure:disk","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":0,"expires_tick":0,"structure_damage":target.hp}
	var change: Dictionary = h.destruction_proposal(state,attack,{"prop_id":target.prop_id,"reached":true,"tick":0,"fraction":1.0})
	state.world = change.world
	var dirty_roundtrip: Dictionary = JSON.parse_string(JSON.stringify(state))
	t.check(H.validate_world(dirty_roundtrip).ok,"JSON dirty world validates canonical integral prop hp")
	var prepared: Dictionary = store.prepare(state.world.delta_root,state.world.dirty_chunks,state.world.world_revision)
	t.check(prepared.ok,"exact immutable world store prepares actual destruction pages")
	if not prepared.ok: return
	var accepted := H.receipt_proposal(state.world,prepared.receipt)
	t.check(accepted.ok,"exact adapter accepts real prepared receipt")
	if not accepted.ok: return
	var durable := state.duplicate(true); durable.world = accepted.world
	var fresh = h.fresh()
	var adapter = Adapter.new(store,H.requirements,func(value,verified):
		var result: Dictionary = fresh.prepare(value,verified)
		return {"ok":true,"state":value.duplicate(true)} if result.ok else result)
	var result: Dictionary = adapter.validate_checkpoint(JSON.parse_string(JSON.stringify(durable)))
	t.check(result.ok,"exact checkpoint adapter verifies full disk root and supplies real helper hydration (world-only, not Core restore)")
	if result.ok:
		var restored := {}
		for chunk in fresh.render_view(result.state).chunks:
			for prop in chunk.props:
				if prop.prop_id == target.prop_id: restored = prop
		t.check(restored.get("destroyed",false),"destroyed building survives real page readback and isolated hydration")
	var bad := durable.duplicate(true); bad.world.delta_root.root_hash = "b".repeat(64)
	t.check(not adapter.validate_checkpoint(bad).ok,"missing disk root fails without recreating empty terrain")

func _structure_admission(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	t.check(h.has_method("structure_candidate_proposal"),"structure admission proposal boundary exists")
	if not h.has_method("structure_candidate_proposal"): return
	h.prepare(state,F.hydration(H.requirements(state)))
	var target := {}
	for chunk in h.render_view(state).chunks:
		if chunk.chunk == ["0","0"]:
			for prop in chunk.props:
				if prop.destructible: target = prop; break
	if target.is_empty(): t.check(false,"admission fixture finds structure"); return
	var actor := {"structure_capable":true,"source_team":"titan","position":[target.ground_footprint.position.x-16,target.ground_footprint.get_center().y]}
	var rules := {"structure_admission_interval_ticks":60,"max_structure_attacks":2,"warning_ticks":20,"recovery_ticks":30,"structure_damage":1,"structure_reach":64}
	var budget := {"remaining_strong_slots":1,"in_flight":0,"next_admit_tick":0}
	var before := state.duplicate(true)
	var candidate: Dictionary = h.structure_candidate_proposal(state,actor,target.prop_id,rules,budget)
	t.check(candidate.ok and state == before,"structure admission uses recovered policy and returns private candidate")
	if not candidate.ok: return
	t.check(candidate.world.next_structure_strike_tick == 60 and candidate.admission.active_tick == 20,"canonical structure clock and warning timing come from real admission")
	state.world = candidate.world
	h.prepare(state,F.hydration(H.requirements(state)))
	t.check(h.structure_candidate_proposal(state,actor,target.prop_id,rules,budget).get("error_code") == "structure_budget","persistent global structure cadence blocks back-to-back admissions")
	actor.source_team = "player"
	t.check(h.structure_candidate_proposal(state,actor,target.prop_id,rules,budget).get("error_code") == "source_policy","player cannot manufacture structure attack")

func _physical_seams(t) -> void:
	for direction in [-1,1]:
		var h = H.new(F.definitions()); var state := F.state(h)
		state.world.origin_chunk = ["9007199254740993","-9007199254740993"]
		h.prepare(state,F.hydration(H.requirements(state)))
		var correct := true
		var rebases := 0
		for step in 40:
			var moved: Dictionary = h.move(H.vec(state.player.position),Vector2(direction*96,0),32)
			if not moved.ok: correct = false; break
			state.player.position = [moved.position.x,moved.position.y]
			var rebased := H.rebase_proposal(state)
			if not rebased.ok: correct = false; break
			state = rebased.state
			if rebased.changed:
				rebases += 1
				if not h.prepare(state,F.hydration(H.requirements(state))).ok: correct = false; break
			var traveled: int = 384+direction*96*(step+1)
			var chunks := int(floor(float(traveled)/768.0))
			correct = correct and state.world.origin_chunk[0] == str(9007199254740993+chunks) and state.player.position == [float(traveled-chunks*768),384.0]
		t.check(correct and rebases == 5,"physical footprint move and five rebases preserve far absolute continuity: "+str(direction))
