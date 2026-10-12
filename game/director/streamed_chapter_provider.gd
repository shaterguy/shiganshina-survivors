extends RefCounted
# NEW candidate provider. The app keeps its finite provider until C4 dispatch is verified.
const Chapters = preload("res://game/director/chapter_catalog.gd")
const World = preload("res://game/combat/world_geometry.gd")
const Helper = preload("res://game/core/streamed_run_world.gd")
const DOCK := "res://chapters/chapter_01/authored_dock.json"
var _derived_key := ""
var _derived_chapter: Dictionary = {}
var _derived_builds := 0
var _derived_hits := 0
func load_chapter(id: String) -> Dictionary:
	var base: Dictionary = Chapters.new().load_chapter(id)
	if not base.get("ok",false):
		_clear_derived()
		return base
	var inputs := []
	for path in ["res://chapters/chapter_01/city_templates.json","res://data/world_props.json","res://assets/manifest.json",DOCK]:
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null or file.get_length() > Chapters.MAX_DEFINITION_BYTES: return _fail("definition_missing")
		var parser := JSON.new()
		if parser.parse(file.get_as_text()) != OK or not parser.data is Dictionary: return _fail("invalid_content_definition")
		inputs.append(parser.data)
	return from_definitions(base.chapter,inputs[0],inputs[1],inputs[2],inputs[3])
func from_definitions(base: Dictionary, templates: Dictionary, props: Dictionary, assets: Dictionary, dock: Dictionary) -> Dictionary:
	var catalog = Chapters.new()
	# Only pure derived validation is reused. load_chapter still freshly reads all
	# source bytes and validates the base chapter before reaching this boundary.
	# Full input validity AND its exact Variant types bind the single entry.
	# Canonical JSON alone would merge int/float arrays and StringName/String
	# keys that the existing geometry validator intentionally treats differently.
	# Neither inputs nor returned values alias this cache.
	var inputs := [base,templates,props,assets,dock]
	var canonical: String = catalog.definition_digest(inputs)
	var key := ""
	if not canonical.is_empty():
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(var_to_bytes(inputs))
		key = canonical+":"+digest.finish().hex_encode()
	if not key.is_empty() and key == _derived_key:
		_derived_hits += 1
		return {"ok":true,"chapter":_derived_chapter.duplicate(true)}
	_clear_derived()
	if key.is_empty(): return _fail("invalid_content_definition")
	_derived_builds += 1
	var result := _build_from_definitions(base,templates,props,assets,dock)
	if result.get("ok",false):
		_derived_chapter = result.chapter.duplicate(true)
		_derived_key = key
	return result
func derived_cache_status() -> Dictionary:
	return {"entries":0 if _derived_key.is_empty() else 1,"builds":_derived_builds,"hits":_derived_hits}
func _clear_derived() -> void:
	_derived_key = ""
	_derived_chapter.clear()
func _build_from_definitions(base: Dictionary, templates: Dictionary, props: Dictionary, assets: Dictionary, dock: Dictionary) -> Dictionary:
	var catalog = Chapters.new()
	# Authored JSON integers arrive as floats. Normalize numbers without changing
	# source dictionaries before exact fixed-array validation and engine adapters.
	dock = catalog._canonical_numbers(dock)
	if not base.get("content_fingerprint") is String or base.content_fingerprint.length() != 64: return _fail("invalid_chapter")
	if not props.get("definitions") is Dictionary or props.definitions.is_empty() or not assets.get("assets") is Dictionary: return _fail("invalid_content_definition")
	var mechanical := {"assets":{}}
	for prop in props.definitions.values():
		if not prop is Dictionary: return _fail("invalid_content_definition")
		for field in ["asset_id","ruin_asset_id"]:
			if not prop.get(field) is String or not assets.assets.get(prop[field]) is Dictionary: return _fail("invalid_asset_metadata")
			var art: Dictionary = assets.assets[prop[field]]
			if not _point(art.get("anchor_px")): return _fail("invalid_asset_metadata")
			for dimension in ["cell_w","cell_h"]:
				if not _integer(art.get(dimension),1,4096): return _fail("invalid_asset_metadata")
			mechanical.assets[prop[field]] = {"anchor_px":art.anchor_px.duplicate(),"cell_w":art.cell_w,"cell_h":art.cell_h}
	if not _dock_valid(dock): return _fail("invalid_dock_definition")
	var definitions := {"templates":templates.duplicate(true),"props":props.duplicate(true),"asset_manifest":mechanical}
	if not Helper.new(definitions).valid(): return _fail("invalid_generator")
	var basis := {"identity_version":1,"base_definition_fingerprint":base.content_fingerprint,"world_mode":"streamed_city","world_definitions":definitions,"authored_dock":dock}
	var chapter := base.duplicate(true)
	chapter.world_mode = "streamed_city"
	chapter.world_geometry = {}
	chapter.world_definitions = definitions
	chapter.authored_dock = dock.duplicate(true)
	chapter.content_identity_kind = "streamed_production_definitions"
	chapter.content_fingerprint = catalog.definition_digest(basis)
	return {"ok":true,"chapter":chapter}
func _dock_valid(dock: Dictionary) -> bool:
	if not dock.get("scene_id") is String or dock.scene_id != "authored_dock": return false
	if not _point(dock.get("entry_position")) or dock.entry_position != [0,0]: return false
	if not dock.get("escape_rect") is Array or dock.escape_rect != [-56,320,112,80]: return false
	if not dock.get("geometry") is Dictionary or dock.geometry.is_empty() or not World.valid(dock.geometry): return false
	return _point(dock.get("final_actor_entry_position")) and World.walkable(Vector2(dock.final_actor_entry_position[0],dock.final_actor_entry_position[1]),32,dock.geometry) and World.walkable(Vector2.ZERO,8,dock.geometry) and World.walkable(Vector2(0,360),8,dock.geometry)
func _point(v: Variant) -> bool:
	if not v is Array or v.size() != 2: return false
	for n in v:
		if not (n is int or n is float) or not is_finite(float(n)) or absf(float(n)) > 4096: return false
	return true
func _integer(v: Variant, low: int, high: int) -> bool:
	return (v is int or v is float) and is_finite(float(v)) and v == floor(v) and v >= low and v <= high
func _fail(code: String) -> Dictionary:
	_clear_derived()
	return {"ok":false,"error_code":code}

# Transaction input protocol; opaque providers do not opt in.
func capture_validation_inputs() -> Dictionary:
	var paths := Chapters.PATHS.duplicate()
	for path in ["assets/manifest.json","chapters/chapter_01/authored_dock.json"]:
		if not path in paths: paths.append(path)
	var sources := {}
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	for path in paths:
		var file := FileAccess.open("res://"+path,FileAccess.READ)
		if file == null: return {"ok":false,"error_code":"content_mismatch"}
		var length := file.get_length()
		if length > Chapters.MAX_DEFINITION_BYTES:
			file.close()
			return {"ok":false,"error_code":"content_mismatch"}
		var bytes := file.get_buffer(length)
		var error := file.get_error()
		file.close()
		if bytes.size() != length or not error in [OK,ERR_FILE_EOF]: return {"ok":false,"error_code":"content_mismatch"}
		sources[path] = bytes
		hash.update(var_to_bytes([path,length]))
		hash.update(bytes)
	return {"ok":true,"sha256":hash.finish().hex_encode(),"sources":sources}
func definitions_from_capture(capture: Dictionary) -> Dictionary:
	var definitions := {}
	for path in capture.sources:
		var parser := JSON.new()
		if parser.parse(capture.sources[path].get_string_from_utf8()) != OK or not parser.data is Dictionary: return {"ok":false,"error_code":"content_mismatch"}
		definitions[path] = parser.data
	var base_definitions := {}
	for path in Chapters.PATHS: base_definitions[path] = definitions[path]
	var base := Chapters.new().from_definitions(Chapters.CHAPTER_ID,base_definitions)
	if not base.get("ok",false): return {"ok":false,"error_code":"content_mismatch"}
	var result := from_definitions(base.chapter,definitions["chapters/chapter_01/city_templates.json"],definitions["data/world_props.json"],definitions["assets/manifest.json"],definitions["chapters/chapter_01/authored_dock.json"])
	if not result.get("ok",false): return {"ok":false,"error_code":"content_mismatch"}
	return {"ok":true,"chapter":result.chapter.duplicate(true),"definitions":definitions.duplicate(true)}
