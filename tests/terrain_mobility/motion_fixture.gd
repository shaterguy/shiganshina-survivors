extends RefCounted
const Core = preload("res://game/core/run_simulation.gd")
const City = preload("res://game/director/streamed_chapter_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const F = preload("res://tests/core/core_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const AF = preload("res://tests/terrain_mobility/anchor_fixture.gd")
const PATH := "res://game/core/player_mobility.gd"
class Provider:
	extends RefCounted
	var chapter: Dictionary
	var version: String
	func _init(rules := "dev5") -> void:
		version = rules
		var source := City.new()
		var base: Dictionary = Chapters.new().load_chapter("chapter_01_shiganshina").chapter
		var definitions: Dictionary = AF.make().definitions
		var dock: Dictionary = HF.read("res://chapters/chapter_01/authored_dock.json")
		chapter = source.from_definitions(base,definitions.templates,definitions.props,definitions.asset_manifest,dock).chapter
	func load_chapter(_id: String) -> Dictionary: return {"ok":true,"chapter":chapter.duplicate(true)}
	func rules_version() -> String: return version
static func seed_for_cast(tick := 1) -> int:
	# Independent documented probability-domain vector. This does not consume
	# either gameplay RNG or manufacture an airborne state.
	for seed in 4096:
		var hash_value := ("player_mobility:v1|%d|%d|0" % [seed,tick]).sha256_text().left(8).hex_to_int()
		if float(hash_value)/4294967296.0 < 1.0-pow(0.25,1.0/60.0): return seed
	return -1
static func make(t, version := "dev5", tick := 0) -> Dictionary:
	# Runtime-load avoids a preload cycle; the canonical fixture uses Provider.
	var fixture = load("res://tests/corridor_mobility/corridor_fixture.gd")
	var result: Dictionary = fixture.make(t,[],[180.0,256.0],["0","0"],version,tick)
	t.check(not result.is_empty() and not result.get("state",{}).has("error_code"),"motion fixture constructs genuine Core state")
	return result
static func available(t) -> bool:
	t.check(FileAccess.file_exists(PATH),"directional mobility authority exists")
	if not FileAccess.file_exists(PATH): return false
	var script = load(PATH)
	t.check(script != null and script.can_instantiate(),"directional mobility authority compiles")
	return script != null and script.can_instantiate()
static func step(s: Dictionary, direction := Vector2.UP, commands: Array = []) -> Array[Dictionary]:
	# Exercise the normal caller's explicit prepare/retry boundary as the view
	# window advances. Tests for atomic refusal call Core directly instead.
	var needed: Dictionary = H.requirements(s.state,commands)
	if needed.get("ok",false) and not s.core._streamed.readiness(s.state,commands).get("ok",false):
		s.hydration = HF.hydration(needed)
		s.core.prepare_world(s.state,s.hydration,commands)
	return F.step(s.core,s.state,direction,commands)
static func reach(s: Dictionary, phase: String) -> bool:
	for tick in 64:
		if s.state.get("player_mobility",{}).get("phase") == phase: return true
		step(s)
	return false
static func vec(value: Array) -> Vector2: return Vector2(value[0],value[1])
static func same(a: Variant,b: Variant) -> bool: return H._same_json(a,b)
