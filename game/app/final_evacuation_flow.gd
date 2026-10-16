extends RefCounted
# Pure scenario adapter. Core remains the sole clock, combat and win authority.
# Call only with the currently prepared Core and a quiescent live snapshot.
const Address = preload("res://game/world/world_address.gd")
const RETIRED_COLLECTIONS := ["entities","projectiles","telegraphs","drops","pending_attacks","pending_evolutions","player_attack_instances","enemy_attack_instances"]
static func prepare(simulation, state: Dictionary, authority: Dictionary, chapter: Dictionary) -> Dictionary:
	if state.is_empty() or not state.has("world") or state.get("phase") != "evacuation": return {"ok":true,"waiting":true}
	if not state.get("pause_reasons",[]).is_empty(): return {"ok":true,"waiting":true,"reason":"paused"}
	if authority.get("checkpoint") == null or authority.checkpoint.get("run_id") != state.get("run_id"): return _fail("authority_mismatch")
	if simulation._streamed == null: return _fail("world_not_ready")
	var helper = simulation._streamed
	var evacuation: Dictionary = state.world.evacuation
	if evacuation.is_empty():
		var selected: Dictionary = helper.passage_proposal(state)
		if not selected.get("ok",false): return selected
		var candidate: Dictionary = authority.duplicate(true)
		candidate.checkpoint = simulation.snapshot(state)
		candidate.checkpoint.world = selected.world.duplicate(true)
		return {"ok":true,"action":"passage_selection","candidate":candidate,"replace_state":false,"notice":"대피 통로로 이동하세요."}
	if state.world.stage == "city":
		var checked: Dictionary = helper.validate_world(state)
		if not checked.get("ok",false): return checked
		if state.player.hp <= 0: return _fail("player_dead")
		# An immutable absolute destination may be arbitrarily far offscreen.
		# Compare exact chunk strings first, so it never becomes a failed local
		# geometry query or a reason to reselect/freeze this running world.
		var location: Dictionary = Address.normalize(state.world.origin_chunk,Vector2(state.player.position[0],state.player.position[1]))
		if not location.get("ok",false): return location
		if location.chunk != evacuation.chunk or not Rect2(336,336,96,96).has_point(location.local):
			return {"ok":true,"waiting":true,"reason":"outside_passage"}
		if not simulation.final_actor_transition_ready(state):
			return {"ok":true,"waiting":true,"reason":"final_actor_busy"}
	var command := transition_command(state)
	var proposal: Dictionary = helper.dock_transition_proposal(state,command,chapter.get("authored_dock",{}))
	if not proposal.get("ok",false):
		if proposal.get("error_code") == "outside_passage": return {"ok":true,"waiting":true,"reason":"outside_passage"}
		return proposal
	if proposal.get("idempotent",false): return {"ok":true,"waiting":true,"reason":"already_applied"}
	var handoff: Dictionary = simulation.final_actor_handoff(state,chapter.authored_dock)
	if not handoff.get("ok",false):
		if handoff.get("error_code") in ["final_actor_busy","blocked_final_entry"]: return {"ok":true,"waiting":true,"reason":handoff.error_code}
		return handoff
	var candidate: Dictionary = authority.duplicate(true)
	var checkpoint: Dictionary = simulation.snapshot(state)
	checkpoint.world = proposal.candidate_world.duplicate(true)
	checkpoint.player.position = [proposal.player_position.x,proposal.player_position.y]
	checkpoint.escape_zone = chapter.authored_dock.escape_rect.duplicate()
	# Core owns actor admission, legal authored placement and warning ownership.
	# Its DTO preserves identity and original phase deadlines on private copies.
	for collection in RETIRED_COLLECTIONS:
		if not checkpoint.has(collection): continue
		var ids: Array = proposal.retire_ids.get(collection,[])
		checkpoint[collection] = checkpoint[collection].filter(func(record): return not _record_id(record) in ids)
	if checkpoint.has("character_skill"): checkpoint.character_skill.pending_cast_id = ""
	if int(checkpoint.world.get("schema_version",1)) == 2:
		# Consume only Core's admitted final record; never clear unrelated data.
		checkpoint.world.dormant.entities = checkpoint.world.dormant.entities.filter(func(entry): return str(entry.record.id) != str(handoff.entity.id))
	checkpoint.entities.append(handoff.entity.duplicate(true))
	checkpoint.telegraphs.append_array(handoff.telegraphs.duplicate(true))
	simulation.transfer_loot_to_dock(checkpoint)
	candidate.checkpoint = checkpoint
	# The helper's scene notice is not a Core event envelope. Do not invent an
	# event sequence or submit it to combat/audio consumers. Present after commit.
	return {"ok":true,"action":"dock_transition","candidate":candidate,"command":command,"replace_state":true,"notice":str(proposal.event.get("text","선착장으로 퇴각"))}
static func transition_command(state: Dictionary) -> Dictionary:
	var passage_id: String = state.world.evacuation.get("passage_id","")
	return {"command_id":"dock:"+(str(state.run_id)+"|"+passage_id).sha256_text(),"kind":"dock_transition","origin_revision":state.world.origin_revision,"payload":{"passage_id":passage_id}}
static func _record_id(record: Dictionary) -> Variant:
	return record.get("id",record.get("attack_instance_id",record.get("attack_id",record.get("entity_id",""))))
static func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}

