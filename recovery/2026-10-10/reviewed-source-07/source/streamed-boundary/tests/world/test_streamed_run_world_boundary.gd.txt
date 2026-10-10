extends RefCounted
# NEW helper review tests only. The fixture does not claim complete Core validity.
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
func run(t) -> void:
	_identity_variants(t)
	_definition_variants(t)
	_hydration_variants(t)
	_proposal_variants(t)
	_cache_and_dispatch(t)
func _failed(t, result: Dictionary, label: String) -> void:
	t.check(result.get("ok") is bool and not result.get("ok",true) and result.get("error_code") is String and not result.get("error_code","").is_empty(),label)
func _identity_variants(t) -> void:
	var base := F.state(H)
	for field in ["mode","generator_revision","template_revision","content_fingerprint","scene_id"]:
		for value in [{},[],null,0,true,Vector2.ZERO]:
			var bad := base.duplicate(true); bad.world[field] = value
			_failed(t,H.validate_world(bad),"malformed world identity returns explicit failure: "+field+"/"+str(typeof(value)))
			if field == "mode": t.check(not H.enabled(bad),"malformed mode query fails closed")
	for value in [{},[],null,0,true]:
		var bad := base.duplicate(true); bad.content_revision = value
		_failed(t,H.validate_world(bad),"malformed run identity returns explicit failure")
	var selected := base.duplicate(true)
	selected.phase = "evacuation"; selected.final_started_tick = 0
	selected.world.evacuation = {"passage_id":"passage:city_v1:0:0","chunk":["0","0"],"selected_tick":0}
	for value in [{},[],null,0,true]:
		var bad := selected.duplicate(true); bad.world.evacuation.passage_id = value
		_failed(t,H.validate_world(bad),"malformed passage identity returns explicit failure")
func _definition_variants(t) -> void:
	for field in ["generator_revision","template_revision","chunk_size","navigation_cell","street_interval","passage_rect"]:
		var bad := F.definitions(); bad.templates[field] = {}
		t.check(not H.new(bad).valid(),"constructor rejects malformed template contract before exact validator: "+field)
	for field in ["player","grounded_titan","physical_attack","straight_projectile","overhead"]:
		var bad := F.definitions(); bad.props.mask_bits[field] = {}
		t.check(not H.new(bad).valid(),"constructor rejects malformed mask assignment: "+field)
	for field in ["rotation_degrees","contact_damage"]:
		var bad := F.definitions(); bad.props.definitions.house_narrow[field] = {}
		t.check(not H.new(bad).valid(),"constructor rejects malformed prop metadata: "+field)
	var bad := F.definitions(); bad.templates.templates[0].slots[0].rotation_degrees = {}
	t.check(not H.new(bad).valid(),"constructor rejects malformed slot rotation")
	for field in ["anchor_px","cell_w","cell_h"]:
		bad = F.definitions(); bad.asset_manifest.assets.house_narrow[field] = {}
		t.check(not H.new(bad).valid(),"constructor rejects malformed referenced asset metadata: "+field)
func _hydration_variants(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	var needed := H.requirements(state); var hydration := F.hydration(needed)
	t.check(h.prepare(state,hydration).ok,"review cache prepares actual city")
	var before: Dictionary = h.render_view(state)
	for value in [{"slot_id":{},"hp":1,"destroyed":false},{"slot_id":[],"hp":1,"destroyed":false},{"slot_id":"x","hp":{},"destroyed":false},{"slot_id":"x","hp":1,"destroyed":{}},null]:
		var bad := hydration.duplicate(true); bad[needed.chunks[0][0]+","+needed.chunks[0][1]] = [value]
		_failed(t,h.prepare(state,bad),"malformed hydration returns failure envelope")
		t.check(h.matches(state) and h.render_view(state) == before,"malformed hydration preserves live cache A")
func _proposal_variants(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	h.prepare(state,F.hydration(H.requirements(state)))
	var target := {}
	for chunk in h.render_view(state).chunks:
		for prop in chunk.props:
			if prop.destructible: target = prop; break
		if not target.is_empty(): break
	t.check(not target.is_empty(),"proposal review uses real generated building")
	if target.is_empty(): return
	var actor := {"structure_capable":true,"source_team":"titan","position":[target.ground_footprint.position.x-16,target.ground_footprint.get_center().y]}
	var rules := {"structure_admission_interval_ticks":60,"max_structure_attacks":2,"warning_ticks":20,"recovery_ticks":30,"structure_damage":1,"structure_reach":64}
	var budget := {"remaining_strong_slots":1,"in_flight":0,"next_admit_tick":0}
	for field in ["source_team","structure_capable","cancelled"]:
		var bad := actor.duplicate(true); bad[field] = {}
		_failed(t,h.structure_candidate_proposal(state,bad,target.prop_id,rules,budget),"malformed structure actor fails: "+field)
	var attack := {"kind":"structure_strike","source_team":"titan","attack_instance_id":"review:hit","target_prop_id":target.prop_id,"hit_target_ids":[],"active_from_tick":0,"expires_tick":0,"structure_damage":1}
	var contact := {"prop_id":target.prop_id,"reached":true,"tick":0,"fraction":1.0}
	for field in ["kind","source_team","attack_instance_id","cancelled","active_from_tick","expires_tick","structure_damage"]:
		var bad := attack.duplicate(true); bad[field] = {}
		_failed(t,h.destruction_proposal(state,bad,contact),"malformed structure attack fails: "+field)
	for field in ["prop_id","reached","tick","fraction"]:
		var bad := contact.duplicate(true); bad[field] = {}
		_failed(t,h.destruction_proposal(state,attack,bad),"malformed structure contact fails: "+field)
	var selected := state.duplicate(true); selected.phase = "evacuation"; selected.final_started_tick = 0
	selected.world.evacuation = {"passage_id":"passage:city_v1:0:0","chunk":["0","0"],"selected_tick":0}
	var command := {"command_id":"review:dock","kind":"dock_transition","origin_revision":0,"payload":{"passage_id":"passage:city_v1:0:0"}}
	for field in ["scene_id","entry_position","escape_rect","geometry"]:
		var dock := F.dock(); dock[field] = {}
		_failed(t,h.dock_transition_proposal(selected,command,dock),"malformed dock definition fails: "+field)
	for field in ["kind","command_id"]:
		var bad := command.duplicate(true); bad[field] = {}
		_failed(t,h.dock_transition_proposal(selected,bad,F.dock()),"malformed dock command fails: "+field)
	var bad_command := command.duplicate(true); bad_command.payload.passage_id = {}
	_failed(t,h.dock_transition_proposal(selected,bad_command,F.dock()),"malformed command passage ID fails")
	for collection in ["entities","projectiles","telegraphs","drops","pending_attacks","pending_evolutions","player_attack_instances","enemy_attack_instances"]:
		for value in [0,[0]]:
			var bad := selected.duplicate(true); bad[collection] = value
			_failed(t,h.dock_transition_proposal(bad,command,F.dock()),"malformed scene retirement collection fails: "+collection)
	for command_value in [{}, {"kind":{}}, {"kind":null}]:
		_failed(t,H.requirements(state,[command_value]),"malformed command kind cannot bypass spatial command checks")
	for field in ["position","radius","hp"]:
		var bad := selected.duplicate(true); bad.player[field] = {}
		h.prepare(selected,F.hydration(H.requirements(selected)))
		_failed(t,h.passage_proposal(bad),"malformed passage player fails: "+field)
		_failed(t,h.dock_transition_proposal(bad,command,F.dock()),"malformed transition player fails: "+field)
		_failed(t,H.escape_status(bad,F.dock()),"malformed escape player fails: "+field)
	var bad := state.duplicate(true); bad.phase = {}
	h.prepare(state,F.hydration(H.requirements(state)))
	_failed(t,h.passage_proposal(bad),"malformed empty-selection phase fails")
func _cache_and_dispatch(t) -> void:
	var h = H.new(F.definitions()); var state := F.state(h)
	h.prepare(state,F.hydration(H.requirements(state)))
	var before: Dictionary = h.render_view(state)
	var b = h.fresh(); var candidate := state.duplicate(true)
	candidate.run_id = "review:B"; candidate.world.origin_chunk = ["-9007199254740993","9007199254740993"]
	t.check(b.prepare(candidate,F.hydration(H.requirements(candidate))).ok,"fresh helper B has independent far-origin geometry")
	t.check(not b.matches(state) and not h.matches(candidate) and h.render_view(state) == before,"fresh B validation cannot adopt or contaminate cache A")
	t.check(h.begin_query_batch(state).ok,"review query batch begins")
	_failed(t,h.props_query(Rect2(8000,384,10,10)),"late props coverage fails explicitly")
	var first: Dictionary = h.query_status()
	h.cover_query(Vector2(384,384),Vector2(394,384),0,999)
	h.move(Vector2(384,384),Vector2(1,0),8)
	t.check(h.query_status() == first,"first late failure remains sticky through later failures and successes")
	var bad := state.duplicate(true); bad.world.mode = "unknown"
	_failed(t,h.begin_query_batch(bad),"malformed batch cannot clear sticky failure")
	t.check(h.query_status() == first,"unsuccessful batch leaves first failure latched")
	t.check(h.begin_query_batch(state).ok and h.query_status().ok,"new ready batch clears sticky failure")
	var rebase := state.duplicate(true); rebase.player.position = [1152,384]
	var proposal := H.rebase_proposal(rebase)
	t.check(proposal.ok and proposal.state.player.position == [384.0,384.0] and proposal.state.world.origin_chunk == ["1","0"],"seam rebase advances absolute address exactly once")
	if proposal.ok:
		var c = h.fresh(); var needed := H.requirements(proposal.state)
		t.check(c.prepare(proposal.state,F.hydration(needed)).ok,"rebased cache C prepares at new origin")
		var old_prop := {}; var new_prop := {}
		for chunk in before.chunks:
			for prop in chunk.props:
				if chunk.chunk == ["1","0"] and prop.collision_mask != 0: old_prop = prop; break
		for chunk in c.render_view(proposal.state).chunks:
			for prop in chunk.props:
				if prop.prop_id == old_prop.get("prop_id"): new_prop = prop
		t.check(not old_prop.is_empty() and not new_prop.is_empty() and new_prop.ground_footprint.position == old_prop.ground_footprint.position-Vector2(768,0),"same absolute building collision footprint shifts once with rebase")
		if not new_prop.is_empty():
			var box: Rect2 = new_prop.ground_footprint
			var start := Vector2(box.position.x-64,box.get_center().y)
			var hit: Dictionary = c.sweep(start,Vector2(box.size.x+128,0),8)
			t.check(hit.ok and hit.hit_prop_id == new_prop.prop_id and hit.fraction < 1,"rebased collision dispatch hits actual city prop identity")
	var dock_state := state.duplicate(true); dock_state.phase = "evacuation"; dock_state.final_started_tick = 0
	dock_state.world.stage = "dock"; dock_state.world.scene_id = "authored_dock"; dock_state.world.origin_revision = 1
	dock_state.world.escape_rect = [-56,320,112,80]
	dock_state.world.evacuation = {"passage_id":"passage:city_v1:0:0","chunk":["0","0"],"selected_tick":0,"transition_command_id":"review:dock","transition_tick":0}
	dock_state.player.position = [0,0]
	t.check(h.prepare(dock_state,{}).ok,"dock explicitly retires helper city cache")
	_failed(t,h.move(Vector2.ZERO,Vector2.ONE,8),"dock never silently dispatches physics to city geometry")
	t.check(h.render_view(dock_state).chunks.is_empty() and h.status().resident_chunks == 0,"dock helper exposes zero city geometry")
