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
	var fixture = load("res://tests/core/new_current_regression_fixture.gd")
	var sim = fixture.simulation(t)
	var valid: Dictionary = sim.new_run(fixture.chapter(),7,fixture.run_config())
	valid.rng_state = "9223372036854775806"
	valid.active_tick = 17999
	valid.survival_tick = 17999
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
