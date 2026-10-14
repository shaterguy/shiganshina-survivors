extends RefCounted
const M = preload("res://game/core/player_mobility.gd")
const F = preload("res://tests/terrain_mobility/motion_fixture.gd")
const HF = preload("res://tests/core_world/new_streamed_helper_fixture.gd")
const H = preload("res://game/core/streamed_run_world.gd")
const AF = preload("res://tests/terrain_mobility/anchor_fixture.gd")
static func slots() -> Array:
	return [AF.slot("left","house_narrow",[144,224]),AF.slot("right","house_narrow",[260,224])]
static func make(t, authored: Array = [], position := [180.0,256.0], origin := ["0","0"], version := "dev5", tick := 0) -> Dictionary:
	var definitions := HF.definitions()
	for template in definitions.templates.templates: template.slots = (slots() if authored.is_empty() else authored).duplicate(true)
	var provider := F.Provider.new(version)
	var built: Dictionary = F.City.new().from_definitions(F.Chapters.new().load_chapter("chapter_01_shiganshina").chapter,definitions.templates,definitions.props,definitions.asset_manifest,HF.read("res://chapters/chapter_01/authored_dock.json"))
	if not built.get("ok",false): print("FIXTURE_FAILURE ",built); return {}
	provider.chapter = built.chapter
	var core := F.Core.new(provider)
	var state := core.new_run(provider.chapter,F.seed_for_cast(tick+1),F.F.run_config())
	state.active_tick = tick
	state.survival_tick = tick
	state.player.position = position.duplicate()
	state.world.origin_chunk = origin.duplicate()
	state.player.attack_ready_ticks.blade_slash = 200000
	var hydration := HF.hydration(H.requirements(state))
	t.check(core.prepare_world(state,hydration).get("ok",false),"corridor fixture prepares exact authored geometry")
	return {"core":core,"state":state,"provider":provider,"hydration":hydration}
static func step(s: Dictionary, direction := Vector2.UP, commands: Array = []) -> Array[Dictionary]: return F.step(s,direction,commands)
