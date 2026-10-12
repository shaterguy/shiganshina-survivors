extends RefCounted
const X = preload("res://tests/fantasy_skills/fantasy_fixture.gd")
const F = preload("res://tests/core/new_current_regression_fixture.gd")
const Core = preload("res://game/core/run_simulation.gd")
const Chapters = preload("res://game/director/chapter_catalog.gd")
class WallProvider:
	extends RefCounted
	func load_chapter(id: String) -> Dictionary:
		var result: Dictionary = X.Provider.new().load_chapter(id)
		result.chapter.world_geometry = {"bounds":[-640,-300,1280,716],"obstacles":[[85,-200,10,400]]}
		result.chapter.content_identity_kind = "fantasy_wall_geometry_fixture"
		result.chapter.content_fingerprint = Chapters.new().definition_digest({"fantasy_wall_geometry":result.chapter})
		return result
func run(t) -> void:
	for skill in ["chain_lightning","fire_zone"]:
		var provider := WallProvider.new()
		var sim := Core.new(provider)
		var state := sim.new_run(provider.load_chapter("chapter_01_shiganshina").chapter,41,F.run_config())
		t.check(not state.has("error_code"),"explicit fantasy wall geometry is a valid current-definition fixture")
		if state.has("error_code"): continue
		state.equipment = {skill:5}
		var events := F.step(sim,state,Vector2.ZERO,[F.spawn("left",[60,0],"brute"),F.spawn("right",[130,0],"brute")])
		var hits := F.types(events,"damage").filter(func(e): return e.payload.source_id == skill)
		t.check(hits.size() == 1 and hits[0].payload.target_id == "left","actual "+skill+" respects solid cover between nearby targets")
		if skill == "fire_zone":
			for tick in 30: events = F.step(sim,state,Vector2.ZERO)
			hits = F.types(events,"damage").filter(func(e): return e.payload.source_id == skill)
			t.check(not hits.any(func(e): return e.payload.target_id == "right"),"later fixed-area pulse still cannot burn through the wall")
