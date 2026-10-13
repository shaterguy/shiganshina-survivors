extends RefCounted
const Catalog = preload("res://game/progression/upgrade_catalog.gd")
const Resolver = preload("res://game/combat/evolved_attack_resolver.gd")
const F = preload("res://tests/progression/progression_test_fixture.gd")
const SHAPES := {"evo_whirlwind":"circle","evo_sky_lance":"line","evo_echo_assault":"sector","evo_wing_squad":"line"}
func run(t) -> void:
	var catalog := Catalog.new()
	var resolver := Resolver.new(catalog)
	for id in SHAPES:
		var recipe: Dictionary = catalog.evolutions.definition(id)
		t.check(not recipe.is_empty(),"distinct final attack pattern exists: "+id)
		if recipe.is_empty(): continue
		var state := F.state()
		state.equipment = {recipe.base_item_id:5}
		for required in recipe.get("required_equipment",[]): state.equipment[required.equipment_id] = int(required.level)
		for required in recipe.required_passives: state.passives[required.passive_id] = int(required.level)
		state.evolutions = {recipe.base_item_id:id}
		state.player.position = [0.0,0.0]
		state.active_tick = 100
		state.attack_seq = 0
		state.player_attack_instances = []
		var proposal := resolver.reserve(state,recipe.base_item_id,Vector2(80,0),Vector2.RIGHT,F.RUN_ID+":attack:1")
		t.check(proposal.get("ok",false),"final attack proposal reserves: "+id)
		if not proposal.get("ok",false): continue
		t.check(proposal.records.size() == 3 and proposal.records[0].shape == SHAPES[id],"evolution changes attack pattern to three authored stages: "+id)
		var changed_geometry := false
		for index in proposal.records.size():
			var record: Dictionary = proposal.records[index]
			t.check(record.stage_index == index and record.stage_count == 3 and record.evolution_id == id,"stage identities carry the selected evolution: "+id)
			if index > 0:
				changed_geometry = changed_geometry or record.radius != proposal.records[0].radius or record.origin != proposal.records[0].origin or record.direction != proposal.records[0].direction
		t.check(changed_geometry,"final evolution has changing range, origin or trajectory: "+id)
		state.attack_seq = 1
		state.player_attack_instances = proposal.records.filter(func(record): return record.execute_tick > state.active_tick)
		t.check(resolver.validate_records(state),"pending final pattern validates for resume: "+id)
		var parsed: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
		t.check(resolver.validate_records(parsed),"JSON resume preserves authored pattern: "+id)
		var bad := state.duplicate(true)
		bad.player_attack_instances[0].damage += 1.0
		t.check(not resolver.validate_records(bad),"tampered damage is refused: "+id)
		bad = state.duplicate(true)
		bad.player_attack_instances.pop_back()
		t.check(not resolver.validate_records(bad),"missing pending stage is refused: "+id)
		if SHAPES[id] == "line":
			var later := state.duplicate(true)
			later.passives.attack_range = 1
			t.check(resolver.validate_records(later),"later range upgrade preserves the earlier complete cast: "+id)
			var mixed := later.duplicate(true)
			mixed.player_attack_instances[0].width *= 1.12
			t.check(not resolver.validate_records(mixed),"line width and length must share one frozen cast-time range scale: "+id)

			var final_only := later.duplicate(true)
			final_only.active_tick = int(final_only.player_attack_instances[-1].execute_tick)-1
			final_only.player_attack_instances = [final_only.player_attack_instances[-1]]
			t.check(resolver.validate_records(final_only),"one remaining line stage retains its frozen dimensions: "+id)
			final_only.player_attack_instances[0].width *= 1.12
			t.check(not resolver.validate_records(final_only),"mixed range scale is rejected even with only the final pending line stage: "+id)
