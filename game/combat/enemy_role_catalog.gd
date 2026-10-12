class_name EnemyRoleCatalog
extends RefCounted
# This catalog is opt-in. Reading or merging it never activates runtime behavior.
const ROLE_IDS := ["walker", "runner", "grabber", "sweeper", "brute", "leaper", "quadruped", "stone_thrower"]
const BODY_RADII := {"walker":18.0,"runner":16.0,"grabber":20.0,"sweeper":20.0,"brute":24.0,"leaper":20.0,"quadruped":18.0,"stone_thrower":24.0}
const KINDS := {"walker":"bite", "runner":"charge", "grabber":"grab", "sweeper":"sweep", "brute":"slam", "leaper":"leap","quadruped":"charge","stone_thrower":"throw"}
const BEHAVIORS := {"walker":"chase", "runner":"runner", "grabber":"grab", "sweeper":"sweep", "brute":"brute", "leaper":"leap","quadruped":"charge","stone_thrower":"throw"}
const PROFILE_FIELDS := ["kind", "trigger_range", "warning_ticks", "active_ticks", "recovery_ticks", "cooldown_ticks", "radius", "length", "width", "arc_degrees", "rush_speed", "airborne_ticks", "threat_cost"]
const DEFINITION_FIELDS := ["name", "hp", "speed", "damage", "xp", "radius", "behavior", "art_id"]
static func read(path: String = "res://data/enemy_roles_ch01_3.json") -> Dictionary:
	if not FileAccess.file_exists(path): return {"ok":false, "error_code":"catalog_not_found", "errors":["catalog file missing"]}
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(path)) != OK:
		return {"ok":false, "error_code":"invalid_json", "errors":[parser.get_error_message()]}
	var errors := validate(parser.data)
	if not errors.is_empty(): return {"ok":false, "error_code":"invalid_catalog", "errors":errors}
	return {"ok":true, "catalog":parser.data.duplicate(true)}
static func validate(value: Variant) -> Array[String]:
	var errors: Array[String] = []
	if not value is Dictionary: return ["catalog must be a dictionary"]
	_keys(value, ["schema_version", "role_revision", "story_year", "roles"], "catalog", errors)
	if not _number(value.get("schema_version"),true,true) or value.schema_version != 1: errors.append("schema_version must be 1")
	if not value.get("role_revision") is String or not value.role_revision in ["enemy_roles.1","enemy_roles.2"]: errors.append("role_revision must be enemy_roles.1 or enemy_roles.2")
	if not _number(value.get("story_year"),true,true) or value.story_year != 845: errors.append("story_year must be 845")
	if not value.get("roles") is Dictionary:
		errors.append("roles must be a dictionary")
		return errors
	var expected: Array = ROLE_IDS.slice(0,6) if value.get("role_revision") is String and value.role_revision == "enemy_roles.1" else ROLE_IDS
	_keys(value.roles, expected, "roles", errors)
	for id in expected:
		if not value.roles.get(id) is Dictionary:
			errors.append(id + " must have definition and profile")
			continue
		var role: Dictionary = value.roles[id]
		_keys(role, ["definition", "profile"], id, errors)
		if role.get("definition") is Dictionary: _definition_errors(role.definition,id,errors)
		else: errors.append(id + ".definition must be a dictionary")
		if role.get("profile") is Dictionary: _profile_errors(role.profile,id,errors)
		else: errors.append(id + ".profile must be a dictionary")
	return errors
static func merge_enemy_definitions(catalog: Dictionary, legacy: Dictionary) -> Dictionary:
	var result := legacy.duplicate(true)
	if not validate(catalog).is_empty(): return result
	for id in catalog.roles: result[id] = catalog.roles[id].definition.duplicate(true)
	return result
static func profile(catalog: Dictionary, enemy_id: String) -> Dictionary:
	if not enemy_id in ROLE_IDS or not catalog.get("roles") is Dictionary: return {}
	var role: Variant = catalog.roles.get(enemy_id)
	if not role is Dictionary or not role.get("profile") is Dictionary: return {}
	return role.profile.duplicate(true)
static func _keys(value: Dictionary, expected: Array, at: String, errors: Array[String]) -> void:
	for key in value:
		if not key in expected: errors.append(at + ": unknown field " + str(key))
	for key in expected:
		if not value.has(key): errors.append(at + ": missing field " + str(key))
static func _number(value: Variant, positive: bool = false, integral: bool = false) -> bool:
	if not (value is int or value is float): return false
	var number := float(value)
	return is_finite(number) and number >= 0.0 and number <= 1000000.0 and (not positive or number > 0.0) and (not integral or number == floor(number))
static func _definition_errors(value: Dictionary, id: String, errors: Array[String]) -> void:
	_keys(value, DEFINITION_FIELDS, id + ".definition", errors)
	if not value.get("name") is String or str(value.get("name", "")).strip_edges().is_empty(): errors.append(id + ": invalid name")
	for field in ["hp", "speed", "damage", "xp", "radius"]:
		if not _number(value.get(field),true,field == "xp"): errors.append(id + ": invalid " + field)
	if not _number(value.get("radius"),true) or float(value.radius) != float(BODY_RADII[id]): errors.append(id + ": body radius differs from approved model")
	if not value.get("behavior") is String or value.behavior != BEHAVIORS[id]: errors.append(id + ": unapproved behavior")
	var art: String = "titan_basic" if id == "walker" else "titan_" + id
	if not value.get("art_id") is String or value.art_id != art: errors.append(id + ": unapproved art identity")
static func _profile_errors(value: Dictionary, id: String, errors: Array[String]) -> void:
	_keys(value, PROFILE_FIELDS, id + ".profile", errors)
	if not value.get("kind") is String or value.kind != KINDS[id]: errors.append(id + ": unapproved attack kind")
	for field in PROFILE_FIELDS:
		if field == "kind": continue
		var integer: bool = str(field).ends_with("_ticks") or field == "threat_cost"
		var positive: bool = field in ["trigger_range", "warning_ticks", "active_ticks", "recovery_ticks", "cooldown_ticks"]
		if not _number(value.get(field),positive,integer): errors.append(id + ": invalid " + field)
	if not _number(value.get("airborne_ticks"),false,true) or value.airborne_ticks != (24 if id == "leaper" else 0): errors.append(id + ": invalid airborne ticks")
	if not _number(value.get("threat_cost"),false,true) or value.threat_cost != (0 if id == "walker" else 1): errors.append(id + ": invalid threat cost")
	var used: Array = {"walker":["radius","arc_degrees"], "runner":["length","width","rush_speed"], "grabber":["length","width"], "sweeper":["radius","width","arc_degrees"], "brute":["radius"], "leaper":["radius"],"quadruped":["length","width","rush_speed"],"stone_thrower":["length","width","rush_speed"]}[id]
	for field in ["radius", "length", "width", "arc_degrees", "rush_speed"]:
		if field in used:
			if not _number(value.get(field),true): errors.append(id + ": required dimension " + field)
		elif not _number(value.get(field)) or value[field] != 0: errors.append(id + ": unused dimension " + field + " must be zero")
	if _number(value.get("arc_degrees")) and float(value.arc_degrees) > 360.0: errors.append(id + ": arc exceeds 360 degrees")
	if id in ["runner","quadruped","stone_thrower"] and _number(value.get("rush_speed")) and _number(value.get("active_ticks")) and _number(value.get("length")):
		if not is_equal_approx(float(value.length),float(value.rush_speed)*float(value.active_ticks)/60.0): errors.append("runner: length must equal timed body travel")

	var reach_field: String = {"walker":"radius","runner":"length","grabber":"length","sweeper":"radius","brute":"radius","leaper":"trigger_range","quadruped":"length","stone_thrower":"length"}[id]
	if _number(value.get("trigger_range"),true) and _number(value.get(reach_field),true) and float(value.trigger_range) > float(value[reach_field]): errors.append(id + ": trigger exceeds actual reach")
