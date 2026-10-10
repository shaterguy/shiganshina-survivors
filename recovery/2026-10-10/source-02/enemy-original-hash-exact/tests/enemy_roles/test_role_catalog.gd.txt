extends RefCounted
const Fixture := preload("res://tests/enemy_roles/role_fixture.gd")
func run(t) -> void:
	var catalog: Dictionary = Fixture.read_catalog(t)
	if catalog.is_empty(): return
	var catalog_api = load("res://game/combat/enemy_role_catalog.gd")
	test_six_roles_only(t, catalog_api, catalog)
	test_copy_merge_and_validation(t, catalog_api, catalog)
	test_wrong_scalar_types(t,catalog_api,catalog)
func test_six_roles_only(t, api, catalog: Dictionary) -> void:
	var keys: Array = catalog.roles.keys()
	keys.sort()
	var expected := Fixture.ROLE_IDS.duplicate()
	expected.sort()
	t.check(keys == expected, "exactly six approved role IDs")
	t.check(catalog.schema_version == 1 and catalog.role_revision == "enemy_roles.1" and catalog.story_year == 845, "approved catalog identity")
	var values := {
		"walker":[32,42,9,4,18,"bite",44,42,8,36,48,52,0,0,70,0,0,0],
		"runner":[24,72,9,5,16,"charge",96,45,42,66,90,0,294,32,0,420,0,1],
		"grabber":[58,50,12,8,20,"grab",190,60,16,84,90,0,210,44,0,0,0,1],
		"sweeper":[65,40,13,8,20,"sweep",110,60,18,78,90,128,0,24,110,0,0,1],
		"brute":[100,30,17,10,24,"slam",88,72,12,96,120,96,0,0,0,0,0,1],
		"leaper":[60,44,15,9,20,"leap",260,66,10,108,120,64,0,0,0,0,24,1]}
	for id in Fixture.ROLE_IDS:
		var role: Dictionary = catalog.roles[id]
		var d: Dictionary = role.definition
		var p: Dictionary = api.profile(catalog,id)
		var actual := [d.hp,d.speed,d.damage,d.xp,d.radius,p.kind,p.trigger_range,p.warning_ticks,p.active_ticks,p.recovery_ticks,p.cooldown_ticks,p.radius,p.length,p.width,p.arc_degrees,p.rush_speed,p.airborne_ticks,p.threat_cost]
		for index in actual.size():
			t.check(actual[index] == values[id][index], "exact approved tuning: " + id + " field " + str(index))
	t.check(catalog.roles.leaper.definition.art_id == "titan_leaper", "leaper art identity is separate from art approval")
	t.check(api.profile(catalog,"boss_charger").is_empty(), "unknown role does not become walker")
func test_copy_merge_and_validation(t, api, catalog: Dictionary) -> void:
	var legacy: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/enemies.json"))
	legacy.erase("walker")
	var before := catalog.duplicate(true)
	var old := legacy.duplicate(true)
	var merged: Dictionary = api.merge_enemy_definitions(catalog,legacy)
	t.check(merged.walker.speed == 42 and merged.runner.speed == 72 and merged.has("leaper"), "explicit merge replaces/adds only normal roles")
	for id in legacy:
		if str(id).begins_with("boss_"): t.check(merged[id] == legacy[id], "legacy boss preserved: " + id)
	merged.runner.hp = 1
	var copy: Dictionary = api.profile(catalog,"runner")
	copy.warning_ticks = 1
	t.check(catalog == before and legacy == old, "merge and profile return deep copies")
	t.check(api.validate(catalog).is_empty(), "shipped catalog validates")
	for mutation in ["fractional_tick", "negative_hp", "nan", "kind", "role", "future_weapon", "airborne", "cost", "unknown_key", "missing_key", "body_radius", "unreachable_trigger"]:
		var bad := catalog.duplicate(true)
		match mutation:
			"fractional_tick": bad.roles.runner.profile.warning_ticks = 45.5
			"negative_hp": bad.roles.runner.definition.hp = -1
			"nan": bad.roles.runner.profile.rush_speed = NAN
			"kind": bad.roles.runner.profile.kind = "throw"
			"role": bad.roles.thrower_original = bad.roles.runner.duplicate(true)
			"future_weapon": bad.roles.runner.definition.art_id = "thunder_spear"
			"airborne": bad.roles.runner.profile.airborne_ticks = 24
			"cost": bad.roles.walker.profile.threat_cost = 1
			"unknown_key": bad.roles.runner.profile.projectile_speed = 300
			"missing_key": bad.roles.runner.profile.erase("width")
			"body_radius": bad.roles.runner.definition.radius = 32
			"unreachable_trigger": bad.roles.brute.profile.trigger_range = 1000
		t.check(not api.validate(bad).is_empty(), "invalid catalog rejected: " + mutation)
	var many := catalog.duplicate(true)
	many.story_year = 850
	many.roles.walker.definition.hp = -1
	many.roles.runner.profile.kind = "magic"
	t.check(api.validate(many).size() >= 3, "validation collects independent errors")
	for bad in [null, [], 3, {"roles":[]}]: t.check(not api.validate(bad).is_empty(), "malformed catalog rejected")
	t.check(not api.read("res://data/no_such_enemy_catalog.json").ok, "missing file returns structured error")

func test_wrong_scalar_types(t,api,catalog: Dictionary) -> void:
	for field in ["schema_version","story_year","role_revision"]:
		for wrong in ["bad",[],{},true,null]:
			var bad := catalog.duplicate(true)
			bad[field] = wrong
			t.check(not api.validate(bad).is_empty(),"header rejects wrong scalar type without exception: " + field)
	for field in CatalogFields():
		for wrong in ["bad",[],{},true,null]:
			var bad := catalog.duplicate(true)
			bad.roles.runner.profile[field] = wrong
			t.check(not api.validate(bad).is_empty(),"profile rejects wrong scalar type without exception: " + field)
	for field in ["behavior","art_id"]:
		var bad := catalog.duplicate(true)
		bad.roles.runner.definition[field] = 3
		t.check(not api.validate(bad).is_empty(),"definition enum rejects numeric type: " + field)
func CatalogFields() -> Array:
	return ["kind","warning_ticks","airborne_ticks","threat_cost","radius"]
