extends RefCounted
func run(t) -> void:
	var exists := FileAccess.file_exists("res://game/contracts/game_contracts.gd")
	t.check(exists, "GameContracts must exist")
	if not exists:
		return
	var script = load("res://game/contracts/game_contracts.gd")
	t.check(script != null and script.can_instantiate(), "GameContracts compiles")
	if script == null or not script.can_instantiate():
		return
	var contract = script.new()
	var valid := {"schema_version":1,"content_revision":"ch01.1","chapter_id":"chapter_01_shiganshina","character_id":"garrison_01","seed":7,"rng_state":"9223372036854775806","active_tick":17999,"survival_tick":17999,"phase":"survival","pause_reasons":[],"player":{"hp":100,"max_hp":100,"position":[0.0,0.0]},"entities":[],"projectiles":[],"drops":[],"telegraphs":[],"equipment":{},"passives":{},"boss_ids_fired":[],"reward_ids_claimed":[],"command_ids_applied":[],"upgrade_offer":{},"pending_offers":[],"stats":{},"next_entity_id":1,"event_seq":0,"final_started_tick":-1,"evacuation_ready":false,"escape_zone":[0,0,32,32]}
	t.check(contract.validate_snapshot(valid).is_empty(), "valid state accepted")
	var roundtrip: Dictionary = JSON.parse_string(JSON.stringify(valid))
	t.check(contract.validate_snapshot(roundtrip).is_empty(), "JSON roundtrip accepted")
	t.check(roundtrip.rng_state == valid.rng_state and roundtrip.survival_tick == 17999, "RNG and tick preserved exactly")
	valid.erase("phase")
	t.check(not contract.validate_snapshot(valid).is_empty(), "missing phase rejected")
	valid.phase = "broken"
	t.check(not contract.validate_snapshot(valid).is_empty(), "unknown phase rejected")
	valid.phase = "survival"
	valid.player.position = [NAN, 0]
	t.check(not contract.validate_snapshot(valid).is_empty(), "nonfinite coordinates rejected")

	valid.player.position = [0,0]
	valid.survival_tick = "broken"
	t.check(not contract.validate_snapshot(valid).is_empty(), "wrong tick type rejected without crash")
	valid.survival_tick = 17999
	valid.content_revision = 4
	t.check(not contract.validate_snapshot(valid).is_empty(), "wrong content revision type rejected")

	t.check(contract._json_safe({&"generated_action":{&"tick":1}}),"Godot-generated StringName dictionary keys are valid JSON keys")
	t.check(not contract._json_safe({1:"numeric key"}),"non-string dictionary keys remain rejected")
	t.check(not contract._json_safe({&"object":RefCounted.new()}),"StringName keys cannot make object values JSON-safe")
	t.check(not contract._json_safe({&"callback":func(): return 1}),"StringName keys cannot make Callable values JSON-safe")
