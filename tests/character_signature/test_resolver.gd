extends RefCounted
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Supplies = preload("res://game/economy/supply_catalog.gd")
const TOKEN := "character:mikasa_unique_attack"
func run(t) -> void:
	var path := "res://game/combat/character_skill_resolver.gd"
	t.check(FileAccess.file_exists(path),"signature resolver exists independently of equipment")
	if not FileAccess.file_exists(path): return
	var resolver = load(path).new()
	var sim = F.simulation(t)
	var config := F.run_config()
	config.character_id = "mikasa_01"
	config.character_skill_revision = 1
	t.check(Supplies.new().run_upgrade_config_valid(config),"revision 1 admitted only by exact known config field")
	var state: Dictionary = sim.new_run(F.chapter(),13,config)
	t.check(state.get("character_skill") == {"ready_tick":0,"next_probe_tick":1,"pending_cast_id":""},"new opted-in Mikasa starts ready")
	if not state.has("character_skill"): return
	t.check(resolver.validate_records(state),"empty initial signature state valid")
	state.active_tick = 10
	state.survival_tick = 10
	state.passives = {"damage":2}
	var cast: String = state.run_id+":attack:1"
	var proposal: Dictionary = resolver.reserve(state,"target",Vector2.RIGHT,cast)
	t.check(proposal.get("ok",false) and proposal.records.size() == 3,"pure reservation emits exactly three stages")
	if not proposal.get("ok",false): return
	for i in 3:
		t.check(proposal.records[i].execute_tick == 10+i*8 and proposal.records[i].target_id == "target" and proposal.records[i].origin_binding == "player","three fixed-target player-bound scheduled ticks")
	t.check(proposal.records[0].damage == 18.0*1.3 and proposal.records[2].damage == 36.0*1.3,"frozen cast-time global damage applies exactly once")
	state.attack_seq = 1
	state.character_skill = {"ready_tick":730,"next_probe_tick":730,"pending_cast_id":cast}
	state.player_attack_instances = proposal.records.slice(1)
	t.check(resolver.validate_records(state),"future stages valid even though target entity does not exist")
	var disk: Dictionary = JSON.parse_string(JSON.stringify(state,"",true,true))
	t.check(resolver.validate_records(disk),"full precision JSON values preserve exact pending contract")
	for field in ["ready_tick","next_probe_tick"]:
		for value in [true,1.5,NAN,INF,-1,2147483648]:
			var bad: Dictionary = state.duplicate(true)
			bad.character_skill[field] = value
			t.check(not resolver.validate_records(bad),"invalid signature clock rejected: "+field)
	for field in ["target_id","damage","stage_index","execute_tick","cast_damage_level","origin_binding","base_item_id","evolution_id","direction"]:
		var bad: Dictionary = state.duplicate(true)
		var changes := {"target_id":"other","damage":23.0,"stage_index":0,"execute_tick":10,"cast_damage_level":3,"origin_binding":"fixed","base_item_id":"blade_slash","evolution_id":"evo_wing_cut","direction":[0,0]}
		bad.player_attack_instances[0][field] = changes[field]
		t.check(not resolver.validate_records(bad),"tampered pending record rejected: "+field)
	var missing: Dictionary = state.duplicate(true)
	missing.player_attack_instances.pop_back()
	t.check(not resolver.validate_records(missing),"missing future stage cannot replay a partial cast")
	var extra: Dictionary = state.duplicate(true)
	extra.player_attack_instances[0].extra = true
	t.check(not resolver.validate_records(extra),"closed record rejects extra field")
	var legacy: Dictionary = state.duplicate(true)
	legacy.run_config.erase("character_skill_revision")
	t.check(not resolver.validate_records(legacy),"revision-less state cannot inject skill runtime or records")
	legacy.erase("character_skill")
	legacy.player_attack_instances = []
	t.check(resolver.validate_records(legacy),"old Mikasa run remains valid without skill")
	t.check(resolver.presentation(legacy).text == "고유 공격 · 다음 출격부터","legacy HUD does not claim missing ability")
	for value in [true,0,2,1.5,"1"]:
		var bad_config := config.duplicate(true)
		bad_config.character_skill_revision = value
		t.check(not Supplies.new().run_upgrade_config_valid(bad_config),"unsupported revision rejected")
	config.character_id = "garrison_01"
	t.check(not Supplies.new().run_upgrade_config_valid(config),"revision cannot attach to another character")
	var ids := [{"id":"z","hp":10,"position":[20,0],"radius":8},{"id":"a","hp":10,"position":[20,0],"radius":8}]
	state.entities = ids
	var query := func(_p,_r): return [0,1]
	var clear := func(_a,_b): return true
	t.check(resolver.choose_target(state,query,clear) == 1,"equal distance target resolves by string identity without RNG")
	var blocked := func(_a,_b): return false
	t.check(resolver.choose_target(state,query,blocked) == -1,"covered acquisition has no target")
