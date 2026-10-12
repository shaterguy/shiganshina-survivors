extends RefCounted
const Provider = preload("res://game/director/streamed_chapter_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
func run(t) -> void:
	var provider = Provider.new()
	var first: Dictionary = provider.load_chapter("chapter_01_shiganshina")
	t.check(first.get("ok",false),"real current definitions validate")
	t.check(provider.has_method("derived_cache_status"),"provider exposes bounded cache diagnostics")
	if not provider.has_method("derived_cache_status"): return
	var before := first.duplicate(true)
	first.chapter.world_definitions.templates.templates.clear()
	var second: Dictionary = provider.load_chapter("chapter_01_shiganshina")
	t.check(second == before,"caller mutations cannot alter cached validated definitions")
	t.check(provider.derived_cache_status() == {"entries":1,"builds":1,"hits":1},"same freshly read content reuses exactly one immutable derived result")
	var base: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	var templates: Dictionary = _read("res://chapters/chapter_01/city_templates.json")
	var props: Dictionary = _read("res://data/world_props.json")
	var art: Dictionary = _read("res://assets/manifest.json")
	var dock: Dictionary = _read(Provider.DOCK)
	t.check(provider.from_definitions(base,templates,props,art,dock) == before,"injected and file definitions share identical result")
	t.check(provider.derived_cache_status().hits == 2,"complete canonical definition equality is reusable")
	var typed_changed := templates.duplicate(true)
	typed_changed.street_interval = [288,480]
	var cold: Dictionary = Provider.new().from_definitions(base,typed_changed,props,art,dock)
	var warm: Dictionary = provider.from_definitions(base,typed_changed,props,art,dock)
	t.check(warm == cold and not cold.get("ok",false),"canonical numeric equality cannot bypass original type-sensitive validator")
	provider.from_definitions(base,templates,props,art,dock)
	var typed_props := props.duplicate(true)
	var defs := {}
	for prop_id in typed_props.definitions: defs[StringName(prop_id)] = typed_props.definitions[prop_id]
	typed_props.definitions = defs
	cold = Provider.new().from_definitions(base,templates,typed_props,art,dock)
	warm = provider.from_definitions(base,templates,typed_props,art,dock)
	t.check(warm == cold,"StringName keys cannot alias String keys in validation reuse")
	provider = Provider.new()
	provider.from_definitions(base,templates,props,art,dock)
	var changed := templates.duplicate(true)
	changed["qa_metadata"] = "different-current-input"
	var newer: Dictionary = provider.from_definitions(base,changed,props,art,dock)
	t.check(newer.get("ok",false) and newer.chapter.content_fingerprint != before.chapter.content_fingerprint,"any included definition change derives its own authority fingerprint")
	t.check(provider.derived_cache_status().entries == 1 and provider.derived_cache_status().builds == 2,"cache stays one entry across changed content")
	var invalid := templates.duplicate(true)
	invalid.chunk_size = 999
	t.check(not provider.from_definitions(base,invalid,props,art,dock).get("ok",false),"invalid current geometry never reuses last valid result")
	t.check(provider.derived_cache_status().entries == 0,"failed changed definitions cannot keep old cache usable")
	t.check(provider.load_chapter("missing_chapter").get("error_code") == "unknown_chapter","fresh chapter selection validation runs before cache")
	t.check(provider.from_definitions(base,templates,props,art,dock) == before,"explicit return to original definitions performs valid rebuild")
	var returned: Dictionary = provider.from_definitions(base,templates,props,art,dock)
	returned.chapter.authored_dock.clear()
	t.check(provider.from_definitions(base,templates,props,art,dock) == before,"every returned nested dictionary is isolated")
	var bad_assets := art.duplicate(true)
	bad_assets["invalid"] = NAN
	t.check(provider.from_definitions(base,templates,props,bad_assets,dock).get("error_code") == "invalid_content_definition","nonfinite current input rejected before cache")
	t.check(provider.derived_cache_status().entries == 0,"noncanonical input clears derived cache")
	provider.load_chapter("chapter_01_shiganshina")
	t.check(provider.derived_cache_status().entries == 1,"real file result warms cache again")
	provider.load_chapter("missing_chapter")
	t.check(provider.derived_cache_status().entries == 0,"early chapter read failure clears stale derived entry too")
func _read(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))
