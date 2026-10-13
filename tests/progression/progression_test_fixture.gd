extends RefCounted
# NEW C1 test-only states. These are progression inputs, not valid full Core saves.
const RUN_ID := "0123456789abcdef0123456789abcdef:1"
static func state() -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = (42 ^ 0x5EED1203) & 0x7fffffff
	return {"chapter_id":"chapter_01_shiganshina","run_id":RUN_ID,"phase":"survival","equipment":{"blade_slash":1},"passives":{},"evolutions":{},"tactical_seals":0,"player":{"level":2},"rules":{"equipment_slots":4,"passive_slots":4,"allowed_equipment_ids":["blade_slash","spin_slash","odm_dash","reentry_combo","wall_cannon","ally_cover"]},"run_config":{"target_evolution_id":"evo_wing_cut"},"view_revision":1,"offer_seq":1,"upgrade_offer":{},"pending_offers":[],"progression_rng_state":str(rng.state),"rng_state":"708718527385777908"}
static func descriptor(level: int = 2, source: String = "level") -> Dictionary:
	return {"offer_id":RUN_ID+":offer:1","source":source,"level_ordinal":level}
static func maxed() -> Dictionary:
	var result := state()
	result.equipment = {"blade_slash":5,"spin_slash":5,"odm_dash":5,"reentry_combo":5}
	result.passives = {"damage":5,"max_health":5,"recovery":5,"armor":5}
	return result
static func ids(options: Array) -> Array:
	var result := []
	for option in options: result.append(option.option_id)
	return result
static func read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

# Explicit preserved-definition tests keep dev4 seal/passive boundaries and RNG
# oracles independently of the current final-stage run contract.
static func legacy_definitions() -> Dictionary:
	return read("res://tests/run_final_evolution/fixtures/dev4-evolutions.json")
static func legacy_catalog():
	return preload("res://game/progression/upgrade_catalog.gd").new(null,null,legacy_definitions())
