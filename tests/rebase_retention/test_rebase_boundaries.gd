extends RefCounted
# Boundary-only companion to the end-to-end rebase oracle. Every admitted
# source uses the exact production Runtime, Core, Disk, helper and generator.
const F = preload("res://tests/live_coverage/live_fixture.gd")

func run(t) -> void:
	var s := _fixture(t)
	if s.is_empty(): return
	var source = s.pair.simulation._streamed
	t.check(source.has_method("_rebase_eligible") and source.has_method("_prepare_rebased"),"rebase retention exposes its private eligibility/preparation boundary")
	if not source.has_method("_rebase_eligible") or not source.has_method("_prepare_rebased"): return
	t.check(source._rebase_eligible(s.pair.state,s.proposal.state,source._hydration),"real world-v1 cold admission is eligible for an ordinary rebase")
	_identity_boundaries(t,s)
	_source_ownership(t,s)
	_persisted_boundaries(t,s)
	_hydration_boundaries(t,s)
	_missing_preparation(t,s)
	_failed_clearance(t,s)
	_nested_independence(t,s)
	_schema_and_coordinates(t)
	_late_counter_rollback(t)

func _fixture(t, origin: Array = ["0","0"], position: Array = [1152.0,384.0], schema: int = 1) -> Dictionary:
	var s := F.make(t)
	if s.is_empty(): return {}
	var state: Dictionary = s.pair.state.duplicate(true)
	state.world.origin_chunk = origin.duplicate()
	state.player.position = position.duplicate()
	state.world.schema_version = schema
	if schema == 2: state.world.dormant = {"entities":[],"drops":[]}
	var pair: Dictionary = s.runtime.refresh_coverage(state)
	t.check(pair.get("ok",false),"rebase fixture cold-admits actual center-street geometry: "+str(origin))
	if not pair.get("ok",false): return {}
	s.pair = pair
	s.proposal = F.H.rebase_proposal(pair.state)
	t.check(s.proposal.get("ok",false) and s.proposal.get("changed",false),"rebase fixture uses the real nonzero origin proposal")
	if not s.proposal.get("ok",false) or not s.proposal.get("changed",false): return {}
	t.check(pair.simulation._can_prepare_live_coverage(pair.state),"rebase fixture owns the actual pre-step Core admission")
	return s

func _source_bytes(source) -> PackedByteArray:
	return var_to_bytes({"definitions":source._definitions,"identity":source._prepared_identity,"stamp":source._stamp,"hydration":source._hydration,"stage":source._stage,"last_status":source._last_status,"query_failure":source._query_failure,"blocked_routes":source._blocked_routes,"chunks":source._world._chunks,"props":source._world._props,"buckets":source._world._buckets,"dirty":source._world._dirty,"origin":source._world._origin,"collision_cache":source._world._collision_bucket_cache,"clearance_cache":source._world._clearance_cache,"coverage_cache":source._world.coverage_cache_stats(),"diagnostics":source._world.diagnostics(),"navigation":source._navigation.diagnostics(),"navigation_grids":source._navigation._grids})

func _capture(s: Dictionary) -> Dictionary:
	var core = s.pair.simulation
	var source = core._streamed
	return {"state":var_to_bytes(s.pair.state),"helper":source,"world":source._world,"navigation":source._navigation,"generator":source._generator,"proof":source._definition_proof,"bytes":_source_bytes(source),"attack":var_to_bytes(core._attack_view_cache),"pending":var_to_bytes(s.runtime._pending)}

func _unchanged(t,s: Dictionary,before: Dictionary,label: String) -> void:
	var core = s.pair.simulation
	var source = core._streamed
	t.check(source == before.helper and source._world == before.world and source._navigation == before.navigation and source._generator == before.generator and source._definition_proof == before.proof,"rebase "+label+" preserves every installed owner")
	t.check(_source_bytes(source) == before.bytes,"rebase "+label+" preserves nested terrain, hydration, identity, diagnostics and caches")
	t.check(var_to_bytes(s.pair.state) == before.state and var_to_bytes(core._attack_view_cache) == before.attack and var_to_bytes(s.runtime._pending) == before.pending,"rebase "+label+" preserves caller state, RNG, attack view and pending authority")

func _ineligible(t,s: Dictionary,previous: Dictionary,proposed: Dictionary,hydration: Dictionary,label: String) -> void:
	var before := _capture(s)
	var inputs := var_to_bytes([previous,proposed,hydration])
	var source = s.pair.simulation._streamed
	t.check(not source._rebase_eligible(previous,proposed,hydration),"rebase boundary selects the unchanged cold lane for "+label)
	var result: Dictionary = source._prepare_rebased(previous,proposed,hydration)
	t.check(not result.get("ok",false) and result.get("error_code","") != "" and not result.has("helper"),"private rebase preparation cannot publish or silently rebuild an ineligible "+label)
	t.check(var_to_bytes([previous,proposed,hydration]) == inputs,"rebase refusal does not rewrite "+label+" inputs")
	_unchanged(t,s,before,label)

func _identity_boundaries(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var prior: Dictionary = s.pair.state
	for field in ["run_id","seed","run_config","origin_unchanged","origin_wrong_normalized","origin_noncanonical","origin_wrong_type","origin_overflow","revision_unchanged","revision_skipped","revision_wrong_type","world_revision","world_schema_transition","world_schema_future","generator_revision","template_revision","next_structure_strike_tick"]:
		var bad: Dictionary = s.proposal.state.duplicate(true)
		match field:
			"run_id": bad.run_id += ":other"
			"seed": bad.seed += 1
			"run_config": bad.run_config.run_serial += 1
			"origin_unchanged": bad.world.origin_chunk = prior.world.origin_chunk.duplicate()
			"origin_wrong_normalized": bad.world.origin_chunk = ["2","0"]
			"origin_noncanonical": bad.world.origin_chunk = ["01","0"]
			"origin_wrong_type": bad.world.origin_chunk = [1,"0"]
			"origin_overflow": bad.world.origin_chunk = ["9223372036854775808","0"]
			"revision_unchanged": bad.world.origin_revision = prior.world.origin_revision
			"revision_skipped": bad.world.origin_revision += 1
			"revision_wrong_type": bad.world.origin_revision = true
			"world_revision": bad.world.world_revision += 1
			"world_schema_transition":
				bad.world.schema_version = 2
				bad.world.dormant = {"entities":[],"drops":[]}
			"world_schema_future": bad.world.schema_version = 3
			"generator_revision": bad.world.generator_revision = "city_v2"
			"template_revision": bad.world.template_revision = "other_template"
			"next_structure_strike_tick": bad.world.next_structure_strike_tick += 1
		_ineligible(t,s,prior,bad,source._hydration,field)
	var stale := prior.duplicate(true)
	stale.world.world_revision += 1
	var proposal: Dictionary = F.H.rebase_proposal(stale)
	t.check(proposal.get("ok",false) and not source.matches(stale),"stale-witness fixture is a valid proposal that the installed source did not prepare")
	if proposal.get("ok",false): _ineligible(t,s,stale,proposal.state,source._hydration,"stale previous-state witness")
	var unadmitted := F.Core.new(s.provider)
	t.check(not unadmitted._can_prepare_live_coverage(prior),"an unadmitted exact Core cannot borrow another Core's rebase witness")
	var legacy := prior.duplicate(true)
	legacy.player_mobility.schema_version = 1
	t.check(not s.pair.simulation._can_prepare_live_coverage(legacy),"actual pre-step Core gate keeps legacy mobility outside retention")

func _source_ownership(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var definitions: Dictionary = source._definitions
	source._definitions = definitions.duplicate(true)
	source._definitions.templates.template_revision = "changed_after_admission"
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"definitions detached from immutable configuration")
	source._definitions = definitions
	var proof = source._definition_proof
	source._definition_proof = F.H.LiveDefinitions.new(source,source._definition_nonce,proof.data)
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"caller-made definition witness")
	source._definition_proof = proof
	var generator = source._generator
	source._generator = F.H.Generator.new(source._definitions.templates,source._definitions.props)
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"replacement generator owner")
	source._generator = generator
	var origin: Array = source._world._origin
	source._world._origin = ["1","0"]
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"physical origin detached from prepared witness")
	source._world._origin = origin
	var seed: int = source._world._seed
	source._world._seed = seed+1
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"physical seed detached from prepared witness")
	source._world._seed = seed
	var world_revision: int = source._world._world_revision
	source._world._world_revision = world_revision+1
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"physical world revision detached from prepared witness")
	source._world._world_revision = world_revision
	source._query_failure = {"ok":false,"error_code":"world_not_ready"}
	_ineligible(t,s,s.pair.state,s.proposal.state,source._hydration,"failed prior query batch")
	source._query_failure = {}
	t.check(source._rebase_eligible(s.pair.state,s.proposal.state,source._hydration),"restoring exact production owners restores rebase eligibility")

func _destructible(source) -> Dictionary:
	for key in source._world.chunk_keys():
		var chunk: Dictionary = source._world._chunks[key]
		for prop in chunk.props:
			if prop.destructible and not prop.destroyed:
				return {"key":key,"chunk":chunk.chunk.duplicate(),"slot_id":prop.slot_id}
	return {}

func _persisted_boundaries(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var selected := _destructible(source)
	t.check(not selected.is_empty(),"rebase persistence fixture uses a real generated destructible slot")
	if selected.is_empty(): return
	var dirty: Dictionary = s.pair.state.duplicate(true)
	dirty.world.world_revision = 1
	dirty.world.dirty_chunks = [{"chunk":selected.chunk,"props":[{"slot_id":selected.slot_id,"hp":0,"destroyed":true}]}]
	var pair: Dictionary = s.runtime.refresh_coverage(dirty)
	t.check(pair.get("ok",false),"rebase persistence fixture cold-admits actual generated dirty geometry")
	if not pair.get("ok",false): return
	var d := s.duplicate()
	d.pair = pair
	d.proposal = F.H.rebase_proposal(pair.state)
	if not d.proposal.get("ok",false):
		t.check(false,"dirty production source has a real rebase proposal")
		return
	var helper = pair.simulation._streamed
	t.check(helper._rebase_eligible(pair.state,d.proposal.state,helper._hydration),"unchanged dirty geometry is a valid rebase control")
	var before := _capture(d)
	var retained: Dictionary = helper._prepare_rebased(pair.state,d.proposal.state,helper._hydration)
	var cold: Dictionary = s.runtime.refresh_coverage(d.proposal.state)
	t.check(retained.get("ok",false) and cold.get("ok",false),"unchanged dirty rebase succeeds through both retained and cold production preparation")
	if retained.get("ok",false) and cold.get("ok",false):
		var candidate = retained.helper
		var oracle = cold.simulation._streamed
		t.check(candidate.render_view(d.proposal.state) == oracle.render_view(cold.state),"dirty reapply retains exact cold prop geometry and chunk revisions")
		t.check(helper._world._chunks[selected.key].geometry_revision == 1 and candidate._world._chunks[selected.key].geometry_revision == 1 and oracle._world._chunks[selected.key].geometry_revision == 1,"retained dirty chunk resets then reapplies once instead of incrementing to revision 2")
		var actual_anchors := _anchor_identities(candidate,d.proposal.state)
		var expected_anchors := _anchor_identities(oracle,cold.state)
		t.check(not expected_anchors.is_empty() and actual_anchors == expected_anchors,"dirty retained rebase preserves every surviving production anchor identity")
	_unchanged(t,d,before,"successful dirty reset/reapply preparation")
	var cleaned: Dictionary = d.proposal.state.duplicate(true)
	cleaned.world.dirty_chunks = []
	t.check(F.H.validate_world(cleaned).get("ok",false),"changed-dirty boundary remains structurally valid")
	_ineligible(t,d,pair.state,cleaned,helper._hydration,"changed dirty records at unchanged world revision")
	var staged: Dictionary = s.disk.prepare(pair.state.world.delta_root,pair.state.world.dirty_chunks,1)
	t.check(staged.get("ok",false),"root boundary stages real production pages")
	if not staged.get("ok",false): return
	var changed_root: Dictionary = d.proposal.state.duplicate(true)
	changed_root.world.delta_root = staged.receipt.candidate_root.duplicate(true)
	t.check(F.H.validate_world(changed_root).get("ok",false) and changed_root.world.delta_root != pair.state.world.delta_root,"root boundary uses a distinct, valid staged root")
	_ineligible(t,d,pair.state,changed_root,helper._hydration,"changed persisted root")

func _anchor_identities(helper,state: Dictionary) -> Dictionary:
	var result := {}
	for prop in helper._world._props.values():
		var anchor: Dictionary = helper._mobility_anchor_record(state,prop)
		if not anchor.is_empty(): result[prop.prop_id] = anchor
	return result

func _hydration_boundaries(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var selected := _destructible(source)
	t.check(not selected.is_empty(),"hydration boundary has a retained real prop")
	if selected.is_empty(): return
	for mode in ["missing","malformed","changed_valid","unknown_slot"]:
		var hydration: Dictionary = source._hydration.duplicate(true)
		match mode:
			"missing": hydration.erase(selected.key)
			"malformed": hydration[selected.key] = {}
			"changed_valid": hydration[selected.key] = [{"slot_id":selected.slot_id,"hp":0,"destroyed":true}]
			"unknown_slot": hydration[selected.key] = [{"slot_id":"not_a_generated_slot","hp":0,"destroyed":true}]
		if mode == "changed_valid":
			var validated: Dictionary = source._generator.hydrate(source._world._chunks[selected.key],hydration[selected.key])
			t.check(validated.get("ok",false),"changed hydration passes real generator validation but differs from retained geometry provenance")
		_ineligible(t,s,s.pair.state,s.proposal.state,hydration,"retained hydration "+mode)

func _missing_preparation(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var command: Dictionary = F.F.spawn("rebase-boundary-unhydrated",[2304.0,384.0],"walker")
	command.origin_revision = s.proposal.state.world.origin_revision
	var commands: Array = [command]
	var needed: Dictionary = F.H.requirements(s.proposal.state,commands)
	t.check(needed.get("ok",false),"new-coverage failure uses a valid production spatial command")
	if not needed.get("ok",false): return
	var missing := []
	for address in needed.chunks:
		var key: String = F.H.Address.key(address)
		if not source._hydration.has(key): missing.append(key)
	t.check(not missing.is_empty(),"spatial command requires actual new, unhydrated absolute chunks")
	if missing.is_empty(): return
	t.check(source._rebase_eligible(s.pair.state,s.proposal.state,source._hydration),"missing new coverage does not masquerade as a changed source witness")
	var before := _capture(s)
	var command_bytes := var_to_bytes(commands)
	var result: Dictionary = source._prepare_rebased(s.pair.state,s.proposal.state,source._hydration,commands)
	t.check(not result.get("ok",false) and result.get("error_code") == "world_not_ready" and result.get("missing_delta_keys",[]) == missing and not result.has("helper"),"actual preparation preserves the exact missing-key refusal without cold fallback")
	t.check(var_to_bytes(commands) == command_bytes,"failed new-coverage preparation preserves spatial commands")
	_unchanged(t,s,before,"missing new-coverage preparation")

func _failed_clearance(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var blocked := {}
	for chunk in source.render_view(s.pair.state).chunks:
		for prop in chunk.props:
			if prop.collision_mask == 0 or prop.ground_footprint.size == Vector2.ZERO: continue
			var point: Vector2 = prop.ground_footprint.get_center()
			var normalized: Dictionary = F.H.Address.normalize(s.pair.state.world.origin_chunk,point)
			if not normalized.get("ok",false) or normalized.offset == Vector2.ZERO: continue
			var previous: Dictionary = s.pair.state.duplicate(true)
			previous.player.position = [point.x,point.y]
			var proposal: Dictionary = F.H.rebase_proposal(previous)
			if not proposal.get("ok",false): continue
			var needed: Dictionary = F.H.requirements(proposal.state)
			if not needed.get("ok",false): continue
			var complete := true
			for address in needed.chunks:
				if not source._hydration.has(F.H.Address.key(address)): complete = false
			if complete:
				blocked = {"previous":previous,"proposal":proposal}
				break
		if not blocked.is_empty(): break
	t.check(not blocked.is_empty(),"clearance failure uses an actual solid inside fully resident production coverage")
	if blocked.is_empty(): return
	t.check(source._rebase_eligible(blocked.previous,blocked.proposal.state,source._hydration),"blocked candidate reaches physical preparation after the exact identity gate")
	var before := _capture(s)
	var input_bytes := var_to_bytes(blocked)
	var result: Dictionary = source._prepare_rebased(blocked.previous,blocked.proposal.state,source._hydration)
	t.check(not result.get("ok",false) and result.get("error_code") == "blocked" and not result.has("helper"),"rebase clearance failure returns blocked without a cold fallback or partial helper")
	t.check(var_to_bytes(blocked) == input_bytes,"failed physical preparation preserves previous/proposed caller records")
	_unchanged(t,s,before,"failed physical clearance")

func _nested_independence(t,s: Dictionary) -> void:
	var source = s.pair.simulation._streamed
	var before := _capture(s)
	var result: Dictionary = source._prepare_rebased(s.pair.state,s.proposal.state,source._hydration)
	t.check(result.get("ok",false),"nested ownership fixture prepares an actual retained rebase")
	if not result.get("ok",false): return
	var candidate = result.helper
	t.check(candidate != source and candidate._world != source._world and candidate._navigation != source._navigation and candidate._generator != source._generator,"retained rebase owns fresh helper, world, navigation and generator")
	var selected := _destructible(candidate)
	t.check(not selected.is_empty() and source._world._chunks.has(selected.key),"nested ownership mutation targets the absolute retained intersection")
	if selected.is_empty() or not source._world._chunks.has(selected.key): return
	var chunk: Dictionary = candidate._world._chunks[selected.key]
	chunk.ports.north[0] += 1
	chunk.street_nodes[0] += Vector2.ONE
	chunk.props[0].hp = -123
	chunk.chunk[0] = "123456789"
	candidate._hydration[selected.key].append({"slot_id":selected.slot_id,"hp":0,"destroyed":true})
	_unchanged(t,s,before,"candidate nested chunk/prop/array mutation")
	var another: Dictionary = source._prepare_rebased(s.pair.state,s.proposal.state,source._hydration)
	t.check(another.get("ok",false) and another.helper.readiness(s.proposal.state).get("ok",false),"a corrupted unpublished candidate cannot poison a second preparation from A")
	_unchanged(t,s,before,"second independent preparation")

func _schema_and_coordinates(t) -> void:
	var schema_two := _fixture(t,["0","0"],[1152.0,384.0],2)
	if not schema_two.is_empty():
		var source = schema_two.pair.simulation._streamed
		t.check(source._rebase_eligible(schema_two.pair.state,schema_two.proposal.state,source._hydration),"stable world schema 2 remains eligible independently of mobility schema 2")
		var result: Dictionary = source._prepare_rebased(schema_two.pair.state,schema_two.proposal.state,source._hydration)
		t.check(result.get("ok",false),"world schema 2 prepares a retained rebase")
		var parked: Dictionary = schema_two.proposal.state.duplicate(true)
		parked.drops = [{"id":parked.next_entity_id,"position":[3456.0,384.0],"xp":1}]
		parked.next_entity_id += 1
		var parking: Dictionary = F.H.Population.apply_to_candidate(parked)
		t.check(parking.get("ok",false) and parked.world.dormant.drops.size() == 1,"dormant exception uses the real population parking operation")
		var cold: Dictionary = schema_two.runtime.refresh_coverage(parked)
		t.check(cold.get("ok",false),"dormant-only proposed state passes full production cold admission")
		if cold.get("ok",false):
			t.check(source._rebase_eligible(schema_two.pair.state,parked,source._hydration),"absolute dormant changes remain excluded by the existing geometry identity")
			var retained: Dictionary = source._prepare_rebased(schema_two.pair.state,parked,source._hydration)
			t.check(retained.get("ok",false) and retained.helper.render_view(parked) == cold.simulation._streamed.render_view(cold.state),"dormant-only change keeps retained terrain equal to the cold oracle")
	for record in [
		{"origin":["-5","-7"],"position":[-384.0,-384.0],"expected":["-6","-8"]},
		{"origin":["9007199254740993","-9007199254740994"],"position":[1152.0,384.0],"expected":["9007199254740994","-9007199254740994"]},
		{"origin":["9223372036854775803","-9223372036854775804"],"position":[1152.0,384.0],"expected":["9223372036854775804","-9223372036854775804"]}
	]:
		var s := _fixture(t,record.origin,record.position)
		if s.is_empty(): continue
		var source = s.pair.simulation._streamed
		t.check(s.proposal.state.world.origin_chunk == record.expected and s.proposal.state.player.position == [384.0,384.0],"signed int64 rebase preserves canonical exact address and floor-normalized local point: "+str(record.origin))
		var before := _capture(s)
		t.check(source._rebase_eligible(s.pair.state,s.proposal.state,source._hydration),"signed int64 source retains exact ownership eligibility")
		var result: Dictionary = source._prepare_rebased(s.pair.state,s.proposal.state,source._hydration)
		t.check(result.get("ok",false),"signed int64 retained candidate prepares without absolute float conversion")
		if result.get("ok",false):
			t.check(result.helper._world._origin == record.expected and result.helper.readiness(s.proposal.state).get("ok",false),"signed int64 candidate is ready under its exact proposed origin")
			var cold: Dictionary = s.runtime.refresh_coverage(s.proposal.state)
			t.check(cold.get("ok",false) and result.helper.render_view(s.proposal.state) == cold.simulation._streamed.render_view(cold.state),"signed int64 retained geometry equals independent production cold preparation")
		_unchanged(t,s,before,"signed int64 preparation")

func _late_counter_rollback(t) -> void:
	# Reuse the existing city_continuity_review MAX_COUNTER rollback boundary,
	# retaining this fixture's real cold-issued live configuration witness.
	var s := _fixture(t)
	if s.is_empty(): return
	var core = s.pair.simulation
	var state: Dictionary = s.pair.state
	state.active_tick = F.Core.MAX_COUNTER
	var source = core._streamed
	var proposal: Dictionary = F.H.rebase_proposal(state)
	t.check(core._can_prepare_live_coverage(state),"late rollback starts with an actually admitted live Core")
	t.check(proposal.get("ok",false) and proposal.get("changed",false),"late rollback starts with a genuine nonzero rebase")
	if not proposal.get("ok",false) or not proposal.get("changed",false): return
	t.check(source._rebase_eligible(state,proposal.state,source._hydration),"late rollback enters retained rebase with the actual pre-step witness")
	var state_bytes := var_to_bytes(state)
	var rng_bytes := var_to_bytes([state.rng_state,state.progression_rng_state])
	var world = source._world
	var navigation = source._navigation
	var chunks := var_to_bytes(world._chunks)
	var identity := var_to_bytes(source._prepared_identity)
	var hydration := var_to_bytes(source._hydration)
	var attack := var_to_bytes(core._attack_view_cache)
	var view: Dictionary = core.world_render_view(state)
	# Zero input avoids an unrelated mobility activation at the exhausted tick.
	var events: Array = F.F.step(core,state,Vector2.ZERO)
	var status: Dictionary = core.step_status()
	t.check(not status.get("ok",false) and status.get("error_code") == "invalid_snapshot" and status.get("errors",[]) == ["invalid_snapshot"],"retained rebase reaches the real late counter-restore refusal")
	t.check(core._role_tick_state.active_tick == F.Core.MAX_COUNTER+1 and core._role_tick_state.world.origin_chunk == proposal.state.world.origin_chunk,"late refusal follows actual candidate rebase and tick advancement")
	t.check(events.is_empty() and var_to_bytes(state) == state_bytes and var_to_bytes([state.rng_state,state.progression_rng_state]) == rng_bytes,"late counter refusal discards every staged event and preserves full state and both RNG streams")
	t.check(core._streamed == source and source._world == world and source._navigation == navigation,"late counter refusal restores the installed helper, world and navigation owners")
	t.check(var_to_bytes(world._chunks) == chunks and var_to_bytes(source._prepared_identity) == identity and var_to_bytes(source._hydration) == hydration and core.world_render_view(state) == view,"late counter refusal preserves old absolute chunks, witness, hydration and rendered geometry")
	t.check(var_to_bytes(core._attack_view_cache) == attack,"late counter refusal preserves the installed attack view")
