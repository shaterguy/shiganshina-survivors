extends RefCounted
const Fixture = preload("res://tests/core/core_fixture.gd")
const Simulation = preload("res://game/core/run_simulation.gd")
const Contracts = preload("res://game/contracts/game_contracts.gd")
func run(t) -> void:
	var sim = load("res://game/core/run_simulation.gd").new()
	var supported := false
	for method in sim.get_method_list():
		if method.name == "new_run": supported = method.args.size() == 3
	t.check(supported,"NEW factory accepts an explicit immutable run_config")
	if not supported: return
	var chapter := Fixture.v2_chapter()
	t.check(chapter.get("content_identity_kind") == "production_definitions","real fixture uses I ChapterCatalog production definition fingerprint")
	for doctrine in ["doctrine_standard","doctrine_mobile","doctrine_artillery"]:
		var config := Fixture.run_config(1,doctrine,"evo_crossfire" if doctrine == "doctrine_artillery" else "evo_wing_cut")
		var chapter_before := chapter.duplicate(true)
		var config_before := config.duplicate(true)
		var state: Dictionary = sim.new_run(chapter,42,config)
		t.check(not state.has("error_code") and state.get("schema_version") == 2,"real constructor creates v2 state for "+doctrine)
		if state.has("error_code"): continue
		t.check(Contracts.new().validate_snapshot(state).is_empty(),"v2 structural contract accepts actual constructor: "+doctrine)
		t.check(state.run_id == config.run_id and state.run_serial == 1 and state.run_config == config,"Core uses exact supplied identity/config")
		t.check(state.rules.content_fingerprint == chapter.content_fingerprint and state.content_revision == "ch01.3-rebuild.7-grabber-hand","run pins current production identity")
		t.check(state.rules.base_hp == (85 if doctrine == "doctrine_mobile" else 100) and state.player.max_hp == state.rules.base_hp,"doctrine HP is preserved")
		t.check(state.rules.base_move_speed == (135 if doctrine == "doctrine_artillery" else 150) and state.rules.move_speed == state.rules.base_move_speed,"doctrine base speed is preserved")
		t.check(state.equipment == ({"wall_cannon":1} if doctrine == "doctrine_artillery" else {"blade_slash":1}),"doctrine start weapon does not silently add blade")
		var expected_passives := {"movement":1} if doctrine == "doctrine_mobile" else ({"fire_interval":1} if doctrine == "doctrine_artillery" else {})
		t.check(state.passives == expected_passives and state.evolutions.is_empty() and state.tactical_seals == 0,"start passives occupy owned slots without evolution/seals")
		t.check(state.active_tick == 0 and state.survival_tick == 0 and state.attack_seq == 0 and state.offer_seq == 0 and state.player_attack_instances.is_empty(),"fresh run has no fabricated combat/growth history")
		t.check(state.progression_rng_state == "2647525101076341191" and state.rng_state == "708718527385777908","seed42 initializes independent pinned Godot RNG streams")
		t.check(chapter == chapter_before and config == config_before,"constructor leaves chapter/config unchanged")
		var snapshot: Dictionary = sim.snapshot(state)
		var restored: Dictionary = sim.restore(JSON.parse_string(JSON.stringify(snapshot,"",true,true)))
		t.check(restored.get("ok",false) and restored.get("state") == state,"real restore accepts and canonically roundtrips initial "+doctrine)
		if restored.get("ok",false):
			restored.state.run_config.doctrine_id = "mutated"
			restored.state.player.position[0] = 999
			t.check(state == snapshot,"restored candidate and source run do not alias")
	_invalid_constructor(t,sim,chapter)
	_invalid_restore(t,sim,chapter)
func _invalid_constructor(t,sim,chapter: Dictionary) -> void:
	for seed in [-1,0.9,1.5,42.9,NAN,INF,2147483648,true,"42"]:
		var rejected: Dictionary = sim.callv("new_run",[chapter,seed,Fixture.run_config()])
		t.check(rejected.get("ok",true) == false,"invalid seed rejected without coercion: "+str(seed))
	for seed in [0,2147483647]:
		var legal: Dictionary = sim.new_run(chapter,seed,Fixture.run_config())
		t.check(legal.get("seed") == seed and sim.restore(legal).get("ok",false),"legal31bit seed endpoint constructs and restores: "+str(seed))
	for patch in [{"run_id":""},{"run_id":"other:1"},{"run_serial":0},{"run_serial":1.5},{"run_serial":2147483648},{"doctrine_id":"unknown"},{"target_evolution_id":"evo_thunder_spear"},{"prepared_supply":"unknown"}]:
		var config := Fixture.run_config()
		config.merge(patch,true)
		t.check(sim.new_run(chapter,42,config).get("error_code") == "invalid_run_config","invalid config fails closed: "+str(patch))
	var config := Fixture.run_config()
	config.extra = 1
	t.check(sim.new_run(chapter,42,config).get("error_code") == "invalid_run_config","unknown persistent config field cannot sneak in")
	var forged := chapter.duplicate(true)
	forged.enemy_catalog.walker.hp = 1
	t.check(not sim.new_run(forged,42,Fixture.run_config()).get("schema_version") == 2,"copying a valid fingerprint does not authorize forged chapter stats")
func _invalid_restore(t,sim,chapter: Dictionary) -> void:
	var state: Dictionary = sim.new_run(chapter,42,Fixture.run_config())
	if state.has("error_code"): return
	var before := state.duplicate(true)
	for key in ["rules","run_id","run_serial","run_config","evolutions","tactical_seals","progression_rng_state","attack_seq","offer_seq","view_revision","player_attack_instances","enemy_attack_instances","evolution_runtime","supply_used"]:
		var invalid := state.duplicate(true)
		invalid.erase(key)
		t.check(not sim.restore(invalid).get("ok",false),"missing required v2 field rejected: "+key)
	for patch in [{"schema_version":1},{"schema_version":3},{"active_tick":1.5},{"active_tick":2147483648},{"survival_tick":1},{"phase":"unknown"},{"run_serial":2},{"tactical_seals":1},{"tactical_seals":6},{"progression_rng_state":"9223372036854775808"},{"progression_rng_state":"+1"},{"supply_used":true}]:
		var invalid := state.duplicate(true)
		invalid.merge(patch,true)
		t.check(not sim.restore(invalid).get("ok",false),"invalid v2 field rejected: "+str(patch))
	for key in ["base_hp","base_move_speed","move_speed","equipment_slots","passive_slots","pickup_radius"]:
		var invalid := state.duplicate(true)
		invalid.rules[key] += 1
		t.check(not sim.restore(invalid).get("ok",false),"immutable rules cannot be forged: "+key)
	var invalid := state.duplicate(true)
	invalid.rules.content_fingerprint = "0".repeat(64)
	t.check(sim.restore(invalid).get("error_code") == "content_mismatch","lost/foreign content fingerprint explicitly rejected")
	invalid = state.duplicate(true)
	invalid.content_revision = "ch01.3"
	t.check(sim.restore(invalid).get("error_code") == "content_mismatch","unknown lost ch01.3 state never silently reinterpreted")
	invalid = state.duplicate(true)
	invalid.world = {}
	t.check(not sim.restore(invalid).get("ok",false),"world presence never falls back to nonstreamed restore")
	invalid = state.duplicate(true)
	invalid.player.position = [NAN,0]
	t.check(not sim.restore(invalid).get("ok",false),"nonfinite player position rejected")
	invalid = state.duplicate(true)
	invalid.equipment.thunder_spear = 1
	t.check(not sim.restore(invalid).get("ok",false),"unknown equipped content rejected")
	invalid = state.duplicate(true)
	invalid.passives = {"damage":1,"armor":1,"movement":1,"recovery":1,"max_health":1}
	t.check(not sim.restore(invalid).get("ok",false),"fifth passive rejected")
	invalid = state.duplicate(true)
	invalid.extra = RefCounted.new()
	t.check(not sim.restore(invalid).get("ok",false),"Object snapshot field rejected without deep-copy alias")
	invalid = state.duplicate(true)
	invalid.extra = {"a":{"b":{"c":{"d":{"e":{"f":{"g":{"h":{"i":{"j":{"k":{"l":{"m":{"n":{"o":{"p":{"q":{"r":{"s":{"t":{"u":{"v":{"w":{"x":{"y":{"z":{"a":{"b":{"c":{"d":{"e":{"f":{"g":{"h":1}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}}
	t.check(not sim.restore(invalid).get("ok",false),"deep hostile input rejected before copying")
	t.check(state == before,"all failed restores leave live state unchanged")
