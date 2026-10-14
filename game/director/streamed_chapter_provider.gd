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
# Exact providers retain their own base catalog; there is no global/shared cache.
const MAX_SOURCE_PROOF_BYTES := 1024 * 1024
var _source_catalog := Chapters.new()
var _cache_mutex := Mutex.new()
var _current_proof: Dictionary = {}
var _capture_proof: Dictionary = {}
var _proof_hits := {"current":0,"capture":0}
var _proof_builds := {"current":0,"capture":0}
const DEV4_FINGERPRINT := "01ad1adb8da30c904fd5feb5d7fb9ce0da0b959d206560d76b382ff1e2b7eae7"
const DEV4_MANIFEST_SHA256 := "01e42d824a111acceb4e64d90bc2c42884824df7a8dabd30c83b8604f67e30cc"
const DEV4_ROOT := "res://data/legacy/dev4/"
var _rules_version := "dev5"
func _init(version: String = "dev5") -> void:
	_rules_version = version
func rules_version() -> String:
	return _rules_version
func load_chapter(id: String) -> Dictionary:
	if _rules_version == "dev5": return _load_current_chapter(id)
	if id != Chapters.CHAPTER_ID: return _fail("unknown_chapter")
	var capture := capture_validation_inputs()
	if not capture.get("ok",false): return _fail("content_mismatch")
	var parsed := definitions_from_capture(capture)
	return {"ok":true,"chapter":parsed.chapter} if parsed.get("ok",false) else _fail("content_mismatch")
func _load_current_chapter(id: String) -> Dictionary:
	var enabled: bool = get_script() == load("res://game/director/streamed_chapter_provider.gd")
	var base: Dictionary = (_source_catalog if enabled else Chapters.new()).load_chapter(id)
	if not base.get("ok",false):
		_clear_source_proofs()
		_clear_derived()
		return base
	var domain := ProjectSettings.globalize_path("res://")
	_cache_mutex.lock()
	var prior := _current_proof
	_cache_mutex.unlock()
	var base_bytes := var_to_bytes(base.chapter) if enabled else PackedByteArray()
	var same: bool = enabled and not prior.is_empty() and prior.domain == domain and prior.version == _rules_version and prior.base_bytes == base_bytes
	var sources := {}
	var inputs := [base.chapter]
	# These are intentionally second reads of templates/props, after base validation.
	for path in ["res://chapters/chapter_01/city_templates.json","res://data/world_props.json","res://assets/manifest.json",DOCK]:
		var file := FileAccess.open(path,FileAccess.READ)
		if file == null or file.get_length() > Chapters.MAX_DEFINITION_BYTES: return _fail("definition_missing")
		var source := file.get_as_text()
		sources[path] = source
		same = same and prior.sources[path] == source
		if same:
			inputs.append(prior.inputs[inputs.size()].duplicate(true))
		else:
			var parser := JSON.new()
			if parser.parse(source) != OK or not parser.data is Dictionary: return _fail("invalid_content_definition")
			inputs.append(parser.data)
	if not enabled: return from_definitions(inputs[0],inputs[1],inputs[2],inputs[3],inputs[4])
	var key: String = prior.key if same else _definition_key(inputs)
	var result := _from_proven_inputs(inputs,key)
	if result.get("ok",false):
		if same: _record_proof_hit("current")
		else: _publish_source_proof("current",{"domain":domain,"version":_rules_version,"sources":sources,"base_bytes":base_bytes,"inputs":inputs,"key":key})
	return result
func from_definitions(base: Dictionary, templates: Dictionary, props: Dictionary, assets: Dictionary, dock: Dictionary) -> Dictionary:
	if get_script() != load("res://game/director/streamed_chapter_provider.gd"):
		return _from_definitions_compat(base,templates,props,assets,dock)
	# Injected inputs always take the original JSON-safety and exact-type key path.
	var inputs := [base,templates,props,assets,dock]
	return _from_proven_inputs(inputs,_definition_key(inputs))
func _from_definitions_compat(base: Dictionary, templates: Dictionary, props: Dictionary, assets: Dictionary, dock: Dictionary) -> Dictionary:
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
func _definition_key(inputs: Array) -> String:
	var canonical: String = Chapters.new().definition_digest(inputs)
	if canonical.is_empty(): return ""
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(var_to_bytes(inputs))
	return canonical+":"+digest.finish().hex_encode()
func _from_proven_inputs(inputs: Array, key: String) -> Dictionary:
	# The private source proof skips only key computation, never this shared cache.
	_cache_mutex.lock()
	if not key.is_empty() and key == _derived_key:
		_derived_hits += 1
		var chapter := _derived_chapter
		_cache_mutex.unlock()
		return {"ok":true,"chapter":chapter.duplicate(true)}
	_derived_key = ""
	_derived_chapter = {}
	if not key.is_empty(): _derived_builds += 1
	_cache_mutex.unlock()
	if key.is_empty(): return _fail("invalid_content_definition")
	var result := _build_from_definitions(inputs[0],inputs[1],inputs[2],inputs[3],inputs[4])
	if result.get("ok",false):
		var chapter: Dictionary = result.chapter.duplicate(true)
		_cache_mutex.lock()
		_derived_chapter = chapter
		_derived_key = key
		_cache_mutex.unlock()
	return result
func derived_cache_status() -> Dictionary:
	_cache_mutex.lock()
	var status := {"entries":0 if _derived_key.is_empty() else 1,"builds":_derived_builds,"hits":_derived_hits}
	_cache_mutex.unlock()
	return status
func _clear_derived() -> void:
	_cache_mutex.lock()
	_derived_key = ""
	_derived_chapter = {}
	_cache_mutex.unlock()
func _clear_source_proofs() -> void:
	_cache_mutex.lock()
	_current_proof = {}
	_capture_proof = {}
	_cache_mutex.unlock()
func _record_proof_hit(lane: String) -> void:
	_cache_mutex.lock()
	_proof_hits[lane] += 1
	_cache_mutex.unlock()
func _publish_source_proof(lane: String, packet: Dictionary) -> void:
	# Inputs are private, already validated, and never mutated after publication.
	packet.payload_bytes = 0
	var size := var_to_bytes(packet).size()
	if size <= MAX_SOURCE_PROOF_BYTES: packet.payload_bytes = size
	else: packet = {}
	_cache_mutex.lock()
	if lane == "current": _current_proof = packet
	else: _capture_proof = packet
	if not packet.is_empty(): _proof_builds[lane] += 1
	_cache_mutex.unlock()
func source_proof_cache_status() -> Dictionary:
	_cache_mutex.lock()
	var status := {}
	for lane in ["current","capture"]:
		var packet: Dictionary = _current_proof if lane == "current" else _capture_proof
		status[lane] = {"entries":0 if packet.is_empty() else 1,"hits":_proof_hits[lane],"builds":_proof_builds[lane],"payload_bytes":packet.get("payload_bytes",0)}
	_cache_mutex.unlock()
	status.base = _source_catalog.source_proof_cache_status()
	return status
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
	_clear_source_proofs()
	_clear_derived()
	return {"ok":false,"error_code":code}

# Transaction input protocol; opaque providers do not opt in.
func capture_validation_inputs() -> Dictionary:
	if not _rules_version in ["dev4","dev5"]: return _fail("content_mismatch")
	var manifest := _legacy_manifest() if _rules_version == "dev4" else {}
	if _rules_version == "dev4" and manifest.is_empty(): return _fail("content_mismatch")
	var sources := {}
	for path in _capture_paths():
		var source: String = DEV4_ROOT+path if _rules_version == "dev4" else "res://"+path
		var file := FileAccess.open(source,FileAccess.READ)
		if file == null: return _fail("content_mismatch")
		var length := file.get_length()
		if length > Chapters.MAX_DEFINITION_BYTES:
			file.close()
			return _fail("content_mismatch")
		var bytes := file.get_buffer(length)
		var error := file.get_error()
		file.close()
		if bytes.size() != length or not error in [OK,ERR_FILE_EOF]: return _fail("content_mismatch")
		if _rules_version == "dev4" and (length != manifest.definition_bytes.get(path) or _bytes_sha256(bytes) != manifest.definition_sha256.get(path)): return _fail("content_mismatch")
		sources[path] = bytes
	return {"ok":true,"rules_version":_rules_version,"sha256":_capture_digest(sources),"sources":sources}
func definitions_from_capture(capture: Dictionary) -> Dictionary:
	if capture.get("rules_version") != _rules_version or not capture.get("sources") is Dictionary: return _fail("content_mismatch")
	var sources: Dictionary = capture.sources
	if sources.size() != _capture_paths().size(): return _fail("content_mismatch")
	var manifest := _legacy_manifest() if _rules_version == "dev4" else {}
	if _rules_version == "dev4" and manifest.is_empty(): return _fail("content_mismatch")
	var enabled: bool = get_script() == load("res://game/director/streamed_chapter_provider.gd")
	var domain := ProjectSettings.globalize_path("res://")
	_cache_mutex.lock()
	var prior := _capture_proof
	_cache_mutex.unlock()
	var same: bool = enabled and not prior.is_empty() and prior.domain == domain and prior.version == _rules_version
	var definitions := {}
	for path in _capture_paths():
		if not sources.get(path) is PackedByteArray or sources[path].size() > Chapters.MAX_DEFINITION_BYTES: return _fail("content_mismatch")
		if _rules_version == "dev4" and (sources[path].size() != manifest.definition_bytes.get(path) or _bytes_sha256(sources[path]) != manifest.definition_sha256.get(path)): return _fail("content_mismatch")
		same = same and prior.sources[path] == sources[path]
		if same:
			definitions[path] = prior.definitions[path].duplicate(true)
		else:
			var parser := JSON.new()
			if parser.parse(sources[path].get_string_from_utf8()) != OK or not parser.data is Dictionary: return _fail("content_mismatch")
			definitions[path] = parser.data
	if capture.get("sha256") != _capture_digest(sources): return _fail("content_mismatch")
	var base: Dictionary
	if same:
		base = {"ok":true,"chapter":prior.inputs[0].duplicate(true)}
	else:
		var base_definitions := {}
		for path in Chapters.PATHS: base_definitions[path] = definitions[path]
		base = Chapters.new().from_definitions(Chapters.CHAPTER_ID,base_definitions)
	if not base.get("ok",false): return _fail("content_mismatch")
	var inputs := [base.chapter,definitions["chapters/chapter_01/city_templates.json"],definitions["data/world_props.json"],definitions["assets/manifest.json"],definitions["chapters/chapter_01/authored_dock.json"]]
	var key: String = (prior.key if same else _definition_key(inputs)) if enabled else ""
	var result := _from_proven_inputs(inputs,key) if enabled else from_definitions(inputs[0],inputs[1],inputs[2],inputs[3],inputs[4])
	if not result.get("ok",false): return _fail("content_mismatch")
	if _rules_version == "dev4" and result.chapter.content_fingerprint != DEV4_FINGERPRINT: return _fail("content_mismatch")
	if enabled:
		if same: _record_proof_hit("capture")
		else: _publish_source_proof("capture",{"domain":domain,"version":_rules_version,"sources":sources.duplicate(true),"definitions":definitions,"inputs":inputs,"key":key})
	return {"ok":true,"chapter":result.chapter.duplicate(true),"definitions":definitions.duplicate(true),"rules_version":_rules_version}
func _capture_paths() -> Array:
	var paths := Chapters.PATHS.duplicate()
	for path in ["assets/manifest.json","chapters/chapter_01/authored_dock.json"]:
		if not path in paths: paths.append(path)
	return paths
func _capture_digest(sources: Dictionary) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(var_to_bytes([_rules_version,DEV4_MANIFEST_SHA256 if _rules_version == "dev4" else ""]))
	for path in _capture_paths():
		hash.update(var_to_bytes([path,sources[path].size()]))
		hash.update(sources[path])
	return hash.finish().hex_encode()
func _legacy_manifest() -> Dictionary:
	var file := FileAccess.open(DEV4_ROOT+"manifest.json",FileAccess.READ)
	if file == null or file.get_length() > Chapters.MAX_DEFINITION_BYTES: return {}
	var bytes := file.get_buffer(file.get_length())
	file.close()
	if _bytes_sha256(bytes) != DEV4_MANIFEST_SHA256: return {}
	var value: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	return value if value is Dictionary else {}
func _bytes_sha256(bytes: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(bytes)
	return hash.finish().hex_encode()
