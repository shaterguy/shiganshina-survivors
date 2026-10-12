extends RefCounted
const Finite = preload("res://tests/core/finite_chapter_provider.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
const Core = preload("res://game/core/run_simulation.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
class Provider:
	extends RefCounted
	func load_chapter(id: String) -> Dictionary:
		var result: Dictionary = Finite.new().load_chapter(id)
		if not result.get("ok",false): return result
		result.chapter.allowed_equipment_ids.append_array(["chain_lightning","fire_zone"])
		result.chapter.evolution_ids.append_array(["evo_storm_chain","evo_inferno_zone"])
		for path in Core.GAMEPLAY_PATHS:
			result.chapter.content_definition_hashes[path] = Chapters.new().definition_digest(JSON.parse_string(FileAccess.get_file_as_string("res://"+path)))
		result.chapter.content_fingerprint = Chapters.new().definition_digest({"fantasy_fixture":1,"chapter":result.chapter})
		return result
static func simulation(): return Core.new(Provider.new())
static func chapter() -> Dictionary: return Provider.new().load_chapter("chapter_01_shiganshina").chapter
static func state(sim, seed := 42) -> Dictionary: return sim.new_run(chapter(),seed,F.run_config())
static func hits(events: Array) -> Array: return events.filter(func(e): return e.type == "damage" and e.payload.get("source_id","") == "chain_lightning")
