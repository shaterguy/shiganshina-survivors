class_name ChapterCatalog
extends RefCounted
const Roles = preload("res://game/combat/enemy_role_catalog.gd")
const World = preload("res://game/combat/world_geometry.gd")
const CHAPTER_ID := "chapter_01_shiganshina"
const CONTENT_REVISION := "ch01.3-rebuild.7-grabber-hand"
const MANIFEST := "chapters/chapter_01/manifest.json"
const MAP := "chapters/chapter_01/map.json"
const MAX_DEFINITION_BYTES := 4 * 1024 * 1024
const MAX_DEFINITION_NODES := 100000
const PATHS := [MANIFEST,MAP,"data/equipment.json","data/passives.json","data/evolutions.json","data/doctrines.json","data/supply_shop.json","data/enemies.json","chapters/chapter_01/city_templates.json","data/world_props.json","data/enemy_roles_ch01_3.json"]

# Private, instance-local success proof. Published packets are never mutated.
const MAX_SOURCE_PROOF_BYTES := 1024 * 1024
var _source_mutex := Mutex.new()
var _file_proof: Dictionary = {}
var _file_proof_hits := 0
var _file_proof_builds := 0

func source_proof_cache_status() -> Dictionary:
	_source_mutex.lock()
	var status := {"entries":0 if _file_proof.is_empty() else 1,"hits":_file_proof_hits,"builds":_file_proof_builds,"payload_bytes":_file_proof.get("payload_bytes",0)}
	_source_mutex.unlock()
	return status

func _file_failure(code: String) -> Dictionary:
	_source_mutex.lock()
	_file_proof = {}
	_source_mutex.unlock()
	return _fail(code)

func definition_paths() -> Array:
	return PATHS.duplicate()

func definition_digest(value: Variant) -> String:
	var budget := [MAX_DEFINITION_NODES]
	if not _json_safe(value,budget): return ""
	return JSON.stringify(_canonical_numbers(value),"",true,true).sha256_text()

func _canonical_numbers(value: Variant) -> Variant:
	# JSON parsers produce floats for integral numbers. Use the same exact integer
	# encoding for injected integers and finite integral floats in the safe range.
	if value is float and value == floor(value) and absf(value) <= 9007199254740991.0:
		return int(value)
	if value is Dictionary:
		var result := {}
		for key in value: result[str(key)] = _canonical_numbers(value[key])
		return result
	if value is Array:
		var result := []
		for item in value: result.append(_canonical_numbers(item))
		return result
	return value

func load_chapter(chapter_id: String) -> Dictionary:
	if chapter_id != CHAPTER_ID: return _file_failure("unknown_chapter")
	var enabled: bool = get_script() == load("res://game/director/chapter_catalog.gd")
	var domain := ProjectSettings.globalize_path("res://")
	_source_mutex.lock()
	var prior := _file_proof
	_source_mutex.unlock()
	var same: bool = enabled and not prior.is_empty() and prior.domain == domain
	var sources := {}
	var definitions := {}
	for path in PATHS:
		var file := FileAccess.open("res://"+path,FileAccess.READ)
		if file == null: return _file_failure("chapter_missing" if path == MANIFEST else "definition_missing")
		if file.get_length() > MAX_DEFINITION_BYTES: return _file_failure("invalid_content_definition")
		# Keep get_as_text and immediate parsing/error order, including short reads.
		var source := file.get_as_text()
		sources[path] = source
		same = same and prior.sources[path] == source
		if same:
			definitions[path] = prior.definitions[path].duplicate(true)
		else:
			var parser := JSON.new()
			if parser.parse(source) != OK or not parser.data is Dictionary: return _file_failure("invalid_content_definition")
			definitions[path] = parser.data
	if same:
		_source_mutex.lock()
		_file_proof_hits += 1
		_source_mutex.unlock()
		return prior.result.duplicate(true)
	var result := from_definitions(chapter_id,definitions)
	if enabled:
		var packet := {}
		if result.get("ok",false):
			packet = {"domain":domain,"sources":sources,"definitions":definitions,"result":result.duplicate(true)}
			packet.payload_bytes = 0
			var size := var_to_bytes(packet).size()
			if size <= MAX_SOURCE_PROOF_BYTES: packet.payload_bytes = size
			else: packet = {}
		_source_mutex.lock()
		_file_proof = packet
		if not packet.is_empty(): _file_proof_builds += 1
		_source_mutex.unlock()
	return result

func from_definitions(chapter_id: String, definitions: Dictionary) -> Dictionary:
	if chapter_id != CHAPTER_ID: return _fail("unknown_chapter")
	if definitions.size() != PATHS.size(): return _fail("invalid_content_definition")
	var budget := [MAX_DEFINITION_NODES]
	if not _json_safe(definitions,budget): return _fail("invalid_content_definition")
	for path in PATHS:
		if not definitions.get(path) is Dictionary: return _fail("invalid_content_definition")
	var chapter: Dictionary = definitions[MANIFEST]
	var enemies: Dictionary = definitions["data/enemies.json"]
	var roles: Dictionary = definitions["data/enemy_roles_ch01_3.json"]
	if not Roles.validate(roles).is_empty() or definition_digest(enemies.get("grabber")) != definition_digest(roles.roles.grabber.definition): return _fail("invalid_enemy_roles")
	if not _chapter_valid(chapter,definitions): return _fail("invalid_chapter")
	var map: Dictionary = definitions[MAP]
	if not map.get("map_id") is String or map.map_id != chapter.map_id or not World.valid(map.get("geometry")) or map.geometry.is_empty(): return _fail("invalid_world_geometry")
	if not World.walkable(Vector2(chapter.spawn_position[0],chapter.spawn_position[1]),8.0,map.geometry): return _fail("invalid_world_geometry")
	var hashes := {}
	for path in PATHS:
		hashes[path] = definition_digest(definitions[path])
	var basis := {"identity_version":1,"chapter_id":CHAPTER_ID,"content_revision":CONTENT_REVISION,"definition_hashes":hashes}
	var result := chapter.duplicate(true)
	result.world_geometry = map.geometry.duplicate(true)
	result.enemy_catalog = enemies.duplicate(true)
	result.enemy_role_catalog = roles.duplicate(true)
	result.content_identity_kind = "production_definitions"
	result.content_definition_hashes = hashes
	result.content_fingerprint = definition_digest(basis)
	return {"ok":true,"chapter":result}

func _chapter_valid(chapter: Dictionary, definitions: Dictionary) -> bool:
	if not chapter.get("chapter_id") is String or chapter.chapter_id != CHAPTER_ID: return false
	if not chapter.get("content_revision") is String or chapter.content_revision != CONTENT_REVISION: return false
	if not _integer(chapter.get("story_year"),845,845): return false
	for field in ["display_name","map_id"]:
		if not chapter.get(field) is String or chapter[field].is_empty(): return false
	if not _numbers(chapter.get("spawn_position"),2) or not _numbers(chapter.get("escape_zone"),4): return false
	if chapter.escape_zone[2] <= 0 or chapter.escape_zone[3] <= 0: return false
	if not chapter.get("clear_rule") is String or chapter.clear_rule != "evacuate_then_exit" or not _integer(chapter.get("evacuation_ticks"),4500,4500): return false
	var references := {"allowed_equipment_ids":"data/equipment.json","doctrine_ids":"data/doctrines.json","evolution_ids":"data/evolutions.json"}
	for field in references:
		var definition: Dictionary = definitions[references[field]]
		if not definition.get("items") is Dictionary or not _ids(chapter.get(field),definition.items): return false
	if not _ids(chapter.get("enemy_ids"),definitions["data/enemies.json"]): return false
	var schedule = chapter.get("boss_schedule")
	if not schedule is Array or schedule.size() != 5: return false
	var seen := {}
	for index in schedule.size():
		var boss = schedule[index]
		if not boss is Dictionary or not _integer(boss.get("tick"),(index+1)*18000,(index+1)*18000): return false
		if not boss.get("boss_id") is String or boss.boss_id != "ch01_b%02d" % ((index+1)*5) or seen.has(boss.boss_id): return false
		if not boss.get("enemy_id") is String or not definitions["data/enemies.json"].has(boss.enemy_id): return false
		seen[boss.boss_id] = true
	var waves = chapter.get("wave_schedule")
	if not waves is Array or waves.is_empty() or waves.size() > 256: return false
	var prior := -1
	for wave in waves:
		if not wave is Dictionary or not _integer(wave.get("tick"),0,107999) or wave.tick <= prior: return false
		if prior == -1 and wave.tick != 0: return false
		if not _integer(wave.get("interval"),1,108000) or not _integer(wave.get("count"),1,512): return false
		prior = int(wave.tick)
	return true

func _ids(value: Variant, known: Dictionary) -> bool:
	if not value is Array or value.is_empty() or value.size() > 256: return false
	var seen := {}
	for id in value:
		if not id is String or id.is_empty() or not known.has(id) or seen.has(id): return false
		seen[id] = true
	return true

func _numbers(value: Variant, count: int) -> bool:
	if not value is Array or value.size() != count: return false
	for number in value:
		if not (number is int or number is float) or not is_finite(float(number)) or absf(float(number)) > 10000000.0: return false
	return true

func _integer(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= low and value <= high

func _json_safe(value: Variant, budget: Array, depth: int = 0) -> bool:
	budget[0] -= 1
	if budget[0] < 0 or depth > 32: return false
	if value == null or value is bool or value is int: return true
	if value is String: return value.length() <= MAX_DEFINITION_BYTES
	if value is float: return is_finite(value)
	if value is Array:
		for item in value:
			if not _json_safe(item,budget,depth+1): return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not _json_safe(value[key],budget,depth+1): return false
		return true
	return false

func _fail(code: String) -> Dictionary:
	return {"ok":false,"error_code":code}
