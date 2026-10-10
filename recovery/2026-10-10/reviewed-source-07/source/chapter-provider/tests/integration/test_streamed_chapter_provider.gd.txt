extends RefCounted
const PATH := "res://game/director/streamed_chapter_provider.gd"
const Chapters = preload("res://game/director/chapter_catalog.gd")
func run(t) -> void:
	t.check(ResourceLoader.exists(PATH),"explicit streamed chapter provider exists")
	if not ResourceLoader.exists(PATH): return
	var provider = load(PATH).new()
	var actual: Dictionary = provider.load_chapter("chapter_01_shiganshina")
	t.check(actual.get("ok",false),"actual streamed chapter definitions load")
	if not actual.get("ok",false): return
	var city: Dictionary = actual.chapter
	var finite: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
	t.check(city.world_mode == "streamed_city" and city.world_geometry.is_empty(),"city has no finite fallback geometry")
	t.check(city.content_fingerprint != finite.content_fingerprint,"finite and city rules have distinct identity")
	t.check(city.authored_dock.scene_id == "authored_dock","dock has explicit independent scene definition")
	t.check(city.authored_dock.escape_rect == [-56,320,112,80],"dock preserves approved physical exit")
	var defs: Dictionary = city.world_definitions.duplicate(true)
	for art in defs.asset_manifest.assets.values():
		t.check(art.size() == 3 and art.has_all(["anchor_px","cell_w","cell_h"]),"mechanical asset projection excludes art source and image hash")
	var rebuilt: Dictionary = provider.from_definitions(finite,defs.templates,defs.props,defs.asset_manifest,city.authored_dock)
	t.check(rebuilt.get("ok",false) and rebuilt.chapter.content_fingerprint == city.content_fingerprint,"injected exact definitions reproduce city identity")
	var changed: Dictionary = defs.asset_manifest.duplicate(true)
	for art in changed.assets.values():
		art.path = "res://new-visual-only.png"
		art.sha256 = "visual-revision"
	t.check(provider.from_definitions(finite,defs.templates,defs.props,changed,city.authored_dock).chapter.content_fingerprint == city.content_fingerprint,"decorative asset change does not invalidate mechanics")
	var dock: Dictionary = city.authored_dock.duplicate(true)
	dock.geometry.obstacles.append([-100,-100,10,10])
	t.check(provider.from_definitions(finite,defs.templates,defs.props,defs.asset_manifest,dock).chapter.content_fingerprint != city.content_fingerprint,"authored dock collision changes identity")
	for hostile in [null,[],{},42]:
		changed = defs.asset_manifest.duplicate(true)
		changed.assets[defs.props.definitions.values()[0].asset_id].anchor_px = hostile
		t.check(not provider.from_definitions(finite,defs.templates,defs.props,changed,city.authored_dock).get("ok",false),"malformed mechanical metadata rejected")
	t.check(not provider.load_chapter("future_chapter").get("ok",false),"unimplemented chapter remains unavailable")
